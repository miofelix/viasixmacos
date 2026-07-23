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
import java.util.concurrent.atomic.AtomicReference
import kotlin.random.Random

/**
 * Userspace IPv4/IPv6 forwarder for full-tunnel mode:
 * - TCP → SOCKS5 CONNECT (mihomo mixed port)
 * - UDP general → SOCKS5 UDP ASSOCIATE **per local client endpoint** (correct demux)
 * - UDP/53 (DNS) → always protected per-query DatagramSocket (concurrent-safe)
 *
 * ASSOCIATE open runs on the worker pool (never blocks the TUN reader). Failures are
 * negative-cached so retries do not stall packet processing.
 */
class Tun2SocksEngine(
    private val vpnService: VpnService,
    private val tun: ParcelFileDescriptor,
    private val socksHost: String,
    private val socksPort: Int,
    private val dnsUpstream: InetAddress = InetAddress.getByName("1.1.1.1"),
    private val maxSessions: Int = 256,
    private val maxUdpClients: Int = 256,
    private val associateFailBackoffMs: Long = 5_000L,
) {
    private val running = AtomicBoolean(false)

    val isRunning: Boolean
        get() = running.get()

    private val sessions = ConcurrentHashMap<String, TcpSession>()
    private val activeSessionCount = AtomicInteger(0)
    private val udpClients = UdpClientEndpointTable(maxEntries = maxUdpClients)
    private val udpRelays = ConcurrentHashMap<String, UdpClientRelay>()
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
        readerThread = null
        writerThread = null
        sessions.values.forEach { it.close() }
        sessions.clear()
        activeSessionCount.set(0)
        closeAllUdpRelays()
        udpClients.clear()
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

    // region IPv4/IPv6 TCP

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

        // DNS: always per-query protected sockets so concurrent A/B queries demux correctly.
        // Never share a single SOCKS reverse-NAT keyed only by remote:53.
        if (udp.destPort == 53) {
            executor.execute {
                forwardDnsDirect(clientIp, udp.sourcePort, remoteIp, payload, ipv6)
            }
            return
        }

        // Drop idle client associates opportunistically (non-blocking).
        for (expired in udpClients.purgeExpired()) {
            closeUdpClient(expired)
        }

        val endpoint =
            UdpClientEndpointTable.Endpoint(
                ip = clientIp,
                port = udp.sourcePort,
                ipv6 = ipv6,
            )
        if (!udpClients.noteActivity(endpoint)) {
            Log.w(TAG, "UDP client limit $maxUdpClients reached; drop")
            return
        }

        val clientKey = endpoint.key()
        val clientRelay =
            udpRelays.computeIfAbsent(clientKey) {
                UdpClientRelay(endpoint)
            }

        val relay = clientRelay.relay.get()
        if (relay != null && relay.isOpen) {
            try {
                relay.send(remoteIp, udp.destPort, payload)
            } catch (error: Exception) {
                Log.w(TAG, "UDP via SOCKS failed: ${error.message}")
                // Drop dead relay; next packet will re-open asynchronously.
                closeUdpClient(endpoint)
            }
            return
        }

        // Negative cache: do not retry ASSOCIATE on every packet after a recent failure.
        val now = System.currentTimeMillis()
        if (now < clientRelay.failedUntilMs.get()) {
            return
        }

        // Queue a small amount of early datagrams while ASSOCIATE opens off the reader thread.
        clientRelay.offerPending(remoteIp, udp.destPort, payload)
        if (clientRelay.opening.compareAndSet(false, true)) {
            executor.execute { openUdpAssociate(clientRelay) }
        }
    }

    private fun openUdpAssociate(clientRelay: UdpClientRelay) {
        if (!running.get()) {
            clientRelay.opening.set(false)
            return
        }
        try {
            val relay =
                Socks5UdpRelay.open(
                    proxyHost = socksHost,
                    proxyPort = socksPort,
                    protect = { socket: Socket -> vpnService.protect(socket) },
                    protectDatagram = { ds: DatagramSocket -> vpnService.protect(ds) },
                )
            if (!running.get()) {
                relay.close()
                clientRelay.opening.set(false)
                return
            }
            clientRelay.relay.set(relay)
            clientRelay.failedUntilMs.set(0L)
            clientRelay.opening.set(false)
            startUdpReceiver(clientRelay, relay)
            // Drain datagrams queued during open.
            while (true) {
                val pending = clientRelay.pollPending() ?: break
                try {
                    relay.send(pending.remote, pending.port, pending.payload)
                } catch (error: Exception) {
                    Log.w(TAG, "UDP pending send failed: ${error.message}")
                    break
                }
            }
            Log.i(
                TAG,
                "SOCKS5 UDP ASSOCIATE ready client=${clientRelay.endpoint.ip.hostAddress}:${clientRelay.endpoint.port}",
            )
        } catch (error: Exception) {
            Log.w(TAG, "SOCKS5 UDP ASSOCIATE failed: ${error.message}")
            clientRelay.failedUntilMs.set(System.currentTimeMillis() + associateFailBackoffMs)
            clientRelay.opening.set(false)
            clientRelay.clearPending()
        }
    }

    private fun startUdpReceiver(clientRelay: UdpClientRelay, relay: Socks5UdpRelay) {
        executor.execute {
            val endpoint = clientRelay.endpoint
            while (running.get() && relay.isOpen) {
                val datagram =
                    try {
                        relay.receive(200)
                    } catch (_: Exception) {
                        break
                    } ?: continue
                // Demux is implicit: this relay only carries traffic for [endpoint].
                enqueuePacket(
                    if (endpoint.ipv6) {
                        Packet.buildIp6Udp(
                            source = datagram.remote,
                            destination = endpoint.ip,
                            sourcePort = datagram.remotePort,
                            destPort = endpoint.port,
                            payload = datagram.payload,
                        )
                    } else {
                        Packet.buildIp4Udp(
                            source = datagram.remote,
                            destination = endpoint.ip,
                            sourcePort = datagram.remotePort,
                            destPort = endpoint.port,
                            payload = datagram.payload,
                        )
                    },
                )
                udpClients.noteActivity(endpoint)
            }
        }
    }

    private fun forwardDnsDirect(
        clientIp: InetAddress,
        clientPort: Int,
        dnsServer: InetAddress,
        payload: ByteArray,
        ipv6: Boolean,
    ) {
        try {
            DatagramSocket().use { socket ->
                vpnService.protect(socket)
                socket.soTimeout = 5_000
                val target =
                    when {
                        dnsServer.isAnyLocalAddress -> dnsUpstream
                        dnsServer.hostAddress == "0.0.0.0" -> dnsUpstream
                        dnsServer.hostAddress == "::" -> dnsUpstream
                        else -> dnsServer
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
                // Reply source is the DNS server the client addressed (or upstream).
                val replySource = if (target == dnsUpstream) dnsServer else target
                val packet =
                    if (ipv6) {
                        Packet.buildIp6Udp(
                            source = replySource,
                            destination = clientIp,
                            sourcePort = 53,
                            destPort = clientPort,
                            payload = bytes,
                        )
                    } else {
                        Packet.buildIp4Udp(
                            source = replySource,
                            destination = clientIp,
                            sourcePort = 53,
                            destPort = clientPort,
                            payload = bytes,
                        )
                    }
                enqueuePacket(packet)
            }
        } catch (error: Exception) {
            Log.w(TAG, "DNS direct forward failed: ${error.message}")
        }
    }

    private fun closeUdpClient(endpoint: UdpClientEndpointTable.Endpoint) {
        udpClients.remove(endpoint)
        val relay = udpRelays.remove(endpoint.key())
        try {
            relay?.relay?.get()?.close()
        } catch (_: Exception) {
        }
        relay?.clearPending()
    }

    private fun closeAllUdpRelays() {
        for (key in udpRelays.keys.toList()) {
            val r = udpRelays.remove(key)
            try {
                r?.relay?.get()?.close()
            } catch (_: Exception) {
            }
            r?.clearPending()
        }
        udpClients.clear()
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

    /**
     * One SOCKS5 UDP ASSOCIATE per local client endpoint so replies demux by relay socket.
     */
    private class UdpClientRelay(
        val endpoint: UdpClientEndpointTable.Endpoint,
    ) {
        val relay = AtomicReference<Socks5UdpRelay?>(null)
        val opening = AtomicBoolean(false)
        val failedUntilMs = AtomicReference(0L)
        private val pending = LinkedBlockingQueue<PendingUdp>(PENDING_CAP)

        fun offerPending(remote: InetAddress, port: Int, payload: ByteArray) {
            if (!pending.offer(PendingUdp(remote, port, payload))) {
                pending.poll()
                pending.offer(PendingUdp(remote, port, payload))
            }
        }

        fun pollPending(): PendingUdp? = pending.poll()

        fun clearPending() {
            pending.clear()
        }

        data class PendingUdp(
            val remote: InetAddress,
            val port: Int,
            val payload: ByteArray,
        )
    }

    companion object {
        private const val TAG = "Tun2SocksEngine"
        private const val PENDING_CAP = 8
    }
}
