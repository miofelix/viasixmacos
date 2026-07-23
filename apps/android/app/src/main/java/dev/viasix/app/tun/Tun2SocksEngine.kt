package dev.viasix.app.tun

import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.random.Random

/**
 * Userspace IPv4/IPv6 forwarder for full-tunnel mode:
 * - TCP → SOCKS5 CONNECT (mihomo mixed port)
 * - UDP → SOCKS5 UDP ASSOCIATE (general, including DNS/53)
 * - Fallback: UDP/53 via protected DatagramSocket if ASSOCIATE is unavailable
 *
 * Typical app traffic (QUIC/HTTP3, DNS, games) is no longer silently dropped.
 */
class Tun2SocksEngine(
    private val vpnService: VpnService,
    private val tun: ParcelFileDescriptor,
    private val socksHost: String,
    private val socksPort: Int,
    private val dnsUpstream: InetAddress = InetAddress.getByName("1.1.1.1"),
    private val maxSessions: Int = 256,
    private val maxUdpFlows: Int = 256,
) {
    private val running = AtomicBoolean(false)
    private val sessions = ConcurrentHashMap<String, TcpSession>()
    private val activeSessionCount = AtomicInteger(0)
    private val udpNat = UdpNatTable(maxEntries = maxUdpFlows)
    private val udpRelayLock = Any()
    @Volatile private var udpRelay: Socks5UdpRelay? = null
    private var udpReceiverThread: Thread? = null
    private var readerThread: Thread? = null
    private var writerThread: Thread? = null
    private val outboundPackets = LinkedBlockingQueue<ByteArray>(512)
    private val executor: ExecutorService =
        Executors.newCachedThreadPool { r ->
            Thread(r, "viasix-tun-worker").apply { isDaemon = true }
        }
    private lateinit var inChannel: FileChannel
    private lateinit var outStream: FileOutputStream

    fun start() {
        if (!running.compareAndSet(false, true)) return
        inChannel = FileInputStream(tun.fileDescriptor).channel
        outStream = FileOutputStream(tun.fileDescriptor)

        writerThread =
            Thread(
                {
                    while (running.get()) {
                        val packet =
                            try {
                                outboundPackets.poll(200, TimeUnit.MILLISECONDS)
                            } catch (_: InterruptedException) {
                                break
                            } ?: continue
                        try {
                            outStream.write(packet)
                            outStream.flush()
                        } catch (error: Exception) {
                            Log.w(TAG, "tun write failed: ${error.message}")
                        }
                    }
                },
                "viasix-tun-writer",
            ).also {
                it.isDaemon = true
                it.start()
            }

        readerThread =
            Thread(
                {
                    val buffer = ByteBuffer.allocate(32767)
                    while (running.get()) {
                        buffer.clear()
                        val len =
                            try {
                                inChannel.read(buffer)
                            } catch (_: Exception) {
                                break
                            }
                        if (len <= 0) continue
                        buffer.flip()
                        handlePacket(buffer)
                    }
                    running.set(false)
                },
                "viasix-tun-reader",
            ).also {
                it.isDaemon = true
                it.start()
            }
        Log.i(TAG, "Tun2SocksEngine started socks=$socksHost:$socksPort (TCP+UDP IPv4/IPv6)")
    }

    fun stop() {
        running.set(false)
        try {
            readerThread?.interrupt()
        } catch (_: Exception) {
        }
        try {
            writerThread?.interrupt()
        } catch (_: Exception) {
        }
        try {
            udpReceiverThread?.interrupt()
        } catch (_: Exception) {
        }
        readerThread = null
        writerThread = null
        udpReceiverThread = null
        sessions.values.forEach { it.close() }
        sessions.clear()
        activeSessionCount.set(0)
        udpNat.clear()
        closeUdpRelay()
        outboundPackets.clear()
        executor.shutdownNow()
        try {
            inChannel.close()
        } catch (_: Exception) {
        }
        try {
            outStream.close()
        } catch (_: Exception) {
        }
        Log.i(TAG, "Tun2SocksEngine stopped")
    }

    private fun handlePacket(buffer: ByteBuffer) {
        when (Packet.ipVersion(buffer)) {
            4 -> {
                val ip = Packet.parseIp4(buffer) ?: return
                when (ip.protocol) {
                    Packet.PROTO_TCP.toInt() -> handleTcp4(buffer, ip)
                    Packet.PROTO_UDP.toInt() -> handleUdp4(buffer, ip)
                }
            }
            6 -> {
                val ip = Packet.parseIp6(buffer) ?: return
                when (ip.nextHeader) {
                    Packet.PROTO_TCP.toInt() -> handleTcp6(buffer, ip)
                    Packet.PROTO_UDP.toInt() -> handleUdp6(buffer, ip)
                }
            }
        }
    }

    // region IPv4 TCP

    private fun handleTcp4(buffer: ByteBuffer, ip: Packet.Ip4) {
        val tcp = Packet.parseTcp(buffer, ip) ?: return
        handleTcpCommon(
            buffer = buffer,
            tcp = tcp,
            clientIp = ip.source,
            remoteIp = ip.destination,
            ipv6 = false,
        )
    }

    private fun handleTcp6(buffer: ByteBuffer, ip: Packet.Ip6) {
        val tcp = Packet.parseTcp(buffer, ip) ?: return
        handleTcpCommon(
            buffer = buffer,
            tcp = tcp,
            clientIp = ip.source,
            remoteIp = ip.destination,
            ipv6 = true,
        )
    }

    private fun handleTcpCommon(
        buffer: ByteBuffer,
        tcp: Packet.Tcp,
        clientIp: InetAddress,
        remoteIp: InetAddress,
        ipv6: Boolean,
    ) {
        val key = key(clientIp, tcp.sourcePort, remoteIp, tcp.destPort)

        if (tcp.flags and Packet.SYN != 0 && tcp.flags and Packet.ACK == 0) {
            if (sessions.containsKey(key)) return
            if (activeSessionCount.get() >= maxSessions) {
                Log.w(TAG, "session limit $maxSessions reached; drop SYN")
                return
            }
            val session =
                TcpSession(
                    clientIp = clientIp,
                    clientPort = tcp.sourcePort,
                    remoteIp = remoteIp,
                    remotePort = tcp.destPort,
                    clientIsn = tcp.seq,
                    ipv6 = ipv6,
                )
            sessions[key] = session
            activeSessionCount.incrementAndGet()
            executor.execute { openTcpSession(key, session) }
            return
        }

        val session = sessions[key] ?: return

        if (tcp.flags and Packet.RST != 0) {
            removeSession(key, session)
            return
        }

        if (!session.handshakeComplete && tcp.flags and Packet.ACK != 0) {
            if (tcp.ack == session.serverSeq) {
                session.handshakeComplete = true
            }
        }

        if (tcp.payloadLength > 0 && session.handshakeComplete && session.socket != null) {
            val payloadEnd = tcp.seq + tcp.payloadLength
            if (payloadEnd <= session.clientNextSeq) {
                enqueueAck(session)
                return
            }
            val skip = (session.clientNextSeq - tcp.seq).coerceAtLeast(0).toInt()
            if (skip >= tcp.payloadLength) {
                enqueueAck(session)
                return
            }

            val payload = ByteArray(tcp.payloadLength - skip)
            val pos = buffer.position()
            buffer.position(tcp.payloadOffset + skip)
            buffer.get(payload)
            buffer.position(pos)
            try {
                session.socket!!.getOutputStream().write(payload)
                session.socket!!.getOutputStream().flush()
                session.clientNextSeq = tcp.seq + tcp.payloadLength
                enqueueAck(session)
            } catch (error: Exception) {
                Log.w(TAG, "tcp write failed: ${error.message}")
                removeSession(key, session)
            }
        }

        if (tcp.flags and Packet.FIN != 0) {
            session.clientNextSeq = tcp.seq + 1
            enqueueAck(session)
            removeSession(key, session)
        }
    }

    private fun openTcpSession(key: String, session: TcpSession) {
        try {
            val socket =
                Socks5Client.connect(
                    socksHost,
                    socksPort,
                    session.remoteIp,
                    session.remotePort,
                )
            if (!running.get()) {
                socket.close()
                removeSession(key, session)
                return
            }
            session.socket = socket
            session.serverSeq = Random.nextInt().toLong() and 0xffffffffL
            session.clientNextSeq = session.clientIsn + 1

            enqueuePacket(
                buildTcpPacket(
                    session = session,
                    seq = session.serverSeq,
                    ack = session.clientNextSeq,
                    flags = Packet.SYN or Packet.ACK,
                    payload = ByteArray(0),
                ),
            )
            session.serverSeq = (session.serverSeq + 1) and 0xffffffffL
            session.handshakeComplete = true

            executor.execute {
                val buf = ByteArray(16 * 1024)
                try {
                    val input = socket.getInputStream()
                    while (running.get() && !socket.isClosed) {
                        val n = input.read(buf)
                        if (n < 0) break
                        if (n == 0) continue
                        val chunk = buf.copyOf(n)
                        enqueuePacket(
                            buildTcpPacket(
                                session = session,
                                seq = session.serverSeq,
                                ack = session.clientNextSeq,
                                flags = Packet.PSH or Packet.ACK,
                                payload = chunk,
                            ),
                        )
                        session.serverSeq = (session.serverSeq + n) and 0xffffffffL
                    }
                } catch (_: Exception) {
                } finally {
                    removeSession(key, session)
                }
            }
        } catch (error: Exception) {
            Log.w(TAG, "SOCKS connect ${session.remoteIp.hostAddress}:${session.remotePort}: ${error.message}")
            enqueuePacket(
                buildTcpPacket(
                    session = session,
                    seq = 0,
                    ack = session.clientIsn + 1,
                    flags = Packet.RST or Packet.ACK,
                    payload = ByteArray(0),
                ),
            )
            removeSession(key, session)
        }
    }

    private fun buildTcpPacket(
        session: TcpSession,
        seq: Long,
        ack: Long,
        flags: Int,
        payload: ByteArray,
    ): ByteArray =
        if (session.ipv6) {
            Packet.buildIp6Tcp(
                source = session.remoteIp,
                destination = session.clientIp,
                sourcePort = session.remotePort,
                destPort = session.clientPort,
                seq = seq,
                ack = ack,
                flags = flags,
                payload = payload,
            )
        } else {
            Packet.buildIp4Tcp(
                source = session.remoteIp,
                destination = session.clientIp,
                sourcePort = session.remotePort,
                destPort = session.clientPort,
                seq = seq,
                ack = ack,
                flags = flags,
                payload = payload,
            )
        }

    // endregion

    // region UDP

    private fun handleUdp4(buffer: ByteBuffer, ip: Packet.Ip4) {
        val udp = Packet.parseUdp(buffer, ip) ?: return
        forwardUdp(
            buffer = buffer,
            udp = udp,
            clientIp = ip.source,
            remoteIp = ip.destination,
            ipv6 = false,
        )
    }

    private fun handleUdp6(buffer: ByteBuffer, ip: Packet.Ip6) {
        val udp = Packet.parseUdp(buffer, ip) ?: return
        forwardUdp(
            buffer = buffer,
            udp = udp,
            clientIp = ip.source,
            remoteIp = ip.destination,
            ipv6 = true,
        )
    }

    private fun forwardUdp(
        buffer: ByteBuffer,
        udp: Packet.Udp,
        clientIp: InetAddress,
        remoteIp: InetAddress,
        ipv6: Boolean,
    ) {
        if (udp.payloadLength < 0) return
        val payload = ByteArray(udp.payloadLength.coerceAtLeast(0))
        if (payload.isNotEmpty()) {
            val pos = buffer.position()
            buffer.position(udp.payloadOffset)
            buffer.get(payload)
            buffer.position(pos)
        }

        if (!udpNat.observeOutbound(clientIp, udp.sourcePort, remoteIp, udp.destPort, ipv6)) {
            Log.w(TAG, "UDP flow limit $maxUdpFlows reached; drop")
            return
        }

        val relay = ensureUdpRelay()
        if (relay != null) {
            try {
                relay.send(remoteIp, udp.destPort, payload)
            } catch (error: Exception) {
                Log.w(TAG, "UDP via SOCKS failed: ${error.message}")
                // DNS fallback when associate path breaks mid-flight
                if (udp.destPort == 53 && !ipv6) {
                    executor.execute {
                        forwardDnsDirect(clientIp, udp.sourcePort, remoteIp, payload)
                    }
                }
            }
            return
        }

        // No SOCKS UDP: keep DNS working so name resolution is not hard-down.
        if (udp.destPort == 53 && !ipv6) {
            executor.execute {
                forwardDnsDirect(clientIp, udp.sourcePort, remoteIp, payload)
            }
        }
    }

    private fun ensureUdpRelay(): Socks5UdpRelay? {
        val existing = udpRelay
        if (existing != null && existing.isOpen) return existing
        synchronized(udpRelayLock) {
            val again = udpRelay
            if (again != null && again.isOpen) return again
            return try {
                val relay =
                    Socks5UdpRelay.open(
                        proxyHost = socksHost,
                        proxyPort = socksPort,
                        protect = { socket: Socket -> vpnService.protect(socket) },
                        protectDatagram = { ds: DatagramSocket -> vpnService.protect(ds) },
                    )
                udpRelay = relay
                startUdpReceiver(relay)
                Log.i(TAG, "SOCKS5 UDP ASSOCIATE ready")
                relay
            } catch (error: Exception) {
                Log.w(TAG, "SOCKS5 UDP ASSOCIATE failed: ${error.message}")
                null
            }
        }
    }

    private fun startUdpReceiver(relay: Socks5UdpRelay) {
        udpReceiverThread?.interrupt()
        udpReceiverThread =
            Thread(
                {
                    while (running.get() && relay.isOpen) {
                        val datagram =
                            try {
                                relay.receive(200)
                            } catch (_: Exception) {
                                break
                            } ?: continue
                        handleSocksUdpInbound(datagram)
                    }
                },
                "viasix-tun-udp-rx",
            ).also {
                it.isDaemon = true
                it.start()
            }
    }

    private fun handleSocksUdpInbound(datagram: Socks5UdpFraming.Datagram) {
        val client =
            udpNat.lookupInbound(datagram.remote, datagram.remotePort) ?: run {
                // No NAT hit: ignore (orphan reply)
                return
            }
        val packet =
            if (client.ipv6) {
                Packet.buildIp6Udp(
                    source = datagram.remote,
                    destination = client.ip,
                    sourcePort = datagram.remotePort,
                    destPort = client.port,
                    payload = datagram.payload,
                )
            } else {
                Packet.buildIp4Udp(
                    source = datagram.remote,
                    destination = client.ip,
                    sourcePort = datagram.remotePort,
                    destPort = client.port,
                    payload = datagram.payload,
                )
            }
        enqueuePacket(packet)
    }

    private fun forwardDnsDirect(
        clientIp: InetAddress,
        clientPort: Int,
        dnsServer: InetAddress,
        payload: ByteArray,
    ) {
        try {
            DatagramSocket().use { socket ->
                vpnService.protect(socket)
                socket.soTimeout = 5_000
                val target =
                    if (dnsServer.isAnyLocalAddress || dnsServer.hostAddress == "0.0.0.0") {
                        dnsUpstream
                    } else {
                        dnsServer
                    }
                val request =
                    DatagramPacket(
                        payload,
                        payload.size,
                        InetSocketAddress(target, 53),
                    )
                socket.send(request)
                val responseBuf = ByteArray(4096)
                val response = DatagramPacket(responseBuf, responseBuf.size)
                socket.receive(response)
                val bytes = response.data.copyOf(response.length)
                enqueuePacket(
                    Packet.buildIp4Udp(
                        source = dnsServer,
                        destination = clientIp,
                        sourcePort = 53,
                        destPort = clientPort,
                        payload = bytes,
                    ),
                )
            }
        } catch (error: Exception) {
            Log.w(TAG, "DNS direct forward failed: ${error.message}")
        }
    }

    private fun closeUdpRelay() {
        synchronized(udpRelayLock) {
            try {
                udpRelay?.close()
            } catch (_: Exception) {
            }
            udpRelay = null
        }
    }

    // endregion

    private fun enqueueAck(session: TcpSession) {
        enqueuePacket(
            buildTcpPacket(
                session = session,
                seq = session.serverSeq,
                ack = session.clientNextSeq,
                flags = Packet.ACK,
                payload = ByteArray(0),
            ),
        )
    }

    private fun enqueuePacket(packet: ByteArray) {
        if (!running.get()) return
        if (!outboundPackets.offer(packet)) {
            outboundPackets.poll()
            outboundPackets.offer(packet)
        }
    }

    private fun removeSession(key: String, session: TcpSession) {
        if (sessions.remove(key, session)) {
            activeSessionCount.updateAndGet { (it - 1).coerceAtLeast(0) }
        }
        session.close()
    }

    private fun key(
        src: InetAddress,
        srcPort: Int,
        dst: InetAddress,
        dstPort: Int,
    ): String = "${src.hostAddress}:$srcPort-${dst.hostAddress}:$dstPort"

    private class TcpSession(
        val clientIp: InetAddress,
        val clientPort: Int,
        val remoteIp: InetAddress,
        val remotePort: Int,
        val clientIsn: Long,
        val ipv6: Boolean = false,
    ) {
        @Volatile var socket: Socket? = null
        @Volatile var serverSeq: Long = 0
        @Volatile var clientNextSeq: Long = 0
        @Volatile var handshakeComplete: Boolean = false

        fun close() {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
            socket = null
        }
    }

    companion object {
        private const val TAG = "Tun2SocksEngine"
    }
}
