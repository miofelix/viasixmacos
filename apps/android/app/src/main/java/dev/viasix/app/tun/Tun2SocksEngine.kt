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
 * Userspace IPv4 forwarder:
 * - TCP → SOCKS5 (mihomo mixed port)
 * - UDP/53 → protected DatagramSocket to upstream DNS
 *
 * Full UDP and IPv6 remain out of scope for this milestone.
 */
class Tun2SocksEngine(
    private val vpnService: VpnService,
    private val tun: ParcelFileDescriptor,
    private val socksHost: String,
    private val socksPort: Int,
    private val dnsUpstream: InetAddress = InetAddress.getByName("1.1.1.1"),
    private val maxSessions: Int = 256,
) {
    private val running = AtomicBoolean(false)
    private val sessions = ConcurrentHashMap<String, TcpSession>()
    private val activeSessionCount = AtomicInteger(0)
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
        Log.i(TAG, "Tun2SocksEngine started socks=$socksHost:$socksPort")
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
        val ip = Packet.parseIp4(buffer) ?: return
        when (ip.protocol) {
            Packet.PROTO_TCP.toInt() -> handleTcp(buffer, ip)
            Packet.PROTO_UDP.toInt() -> handleUdp(buffer, ip)
        }
    }

    private fun handleTcp(buffer: ByteBuffer, ip: Packet.Ip4) {
        val tcp = Packet.parseTcp(buffer, ip) ?: return
        val key = key(ip.source, tcp.sourcePort, ip.destination, tcp.destPort)

        // Client SYN (new connection)
        if (tcp.flags and Packet.SYN != 0 && tcp.flags and Packet.ACK == 0) {
            if (sessions.containsKey(key)) return
            if (activeSessionCount.get() >= maxSessions) {
                Log.w(TAG, "session limit $maxSessions reached; drop SYN")
                return
            }
            val session =
                TcpSession(
                    clientIp = ip.source,
                    clientPort = tcp.sourcePort,
                    remoteIp = ip.destination,
                    remotePort = tcp.destPort,
                    clientIsn = tcp.seq,
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

        // Complete handshake on client ACK after our SYN-ACK.
        if (!session.handshakeComplete && tcp.flags and Packet.ACK != 0) {
            if (tcp.ack == session.serverSeq) {
                session.handshakeComplete = true
            }
        }

        if (tcp.payloadLength > 0 && session.handshakeComplete && session.socket != null) {
            // Drop retransmitted segments that are entirely before clientNextSeq.
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
            // ACK FIN then tear down.
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

            // SYN-ACK to client
            enqueuePacket(
                Packet.buildIp4Tcp(
                    source = session.remoteIp,
                    destination = session.clientIp,
                    sourcePort = session.remotePort,
                    destPort = session.clientPort,
                    seq = session.serverSeq,
                    ack = session.clientNextSeq,
                    flags = Packet.SYN or Packet.ACK,
                    payload = ByteArray(0),
                ),
            )
            session.serverSeq = (session.serverSeq + 1) and 0xffffffffL
            // Mark handshake complete optimistically after SYN-ACK; client ACK hardens it.
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
                            Packet.buildIp4Tcp(
                                source = session.remoteIp,
                                destination = session.clientIp,
                                sourcePort = session.remotePort,
                                destPort = session.clientPort,
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
            Log.w(TAG, "SOCKS connect ${session.remoteIp}:${session.remotePort}: ${error.message}")
            enqueuePacket(
                Packet.buildIp4Tcp(
                    source = session.remoteIp,
                    destination = session.clientIp,
                    sourcePort = session.remotePort,
                    destPort = session.clientPort,
                    seq = 0,
                    ack = session.clientIsn + 1,
                    flags = Packet.RST or Packet.ACK,
                    payload = ByteArray(0),
                ),
            )
            removeSession(key, session)
        }
    }

    private fun handleUdp(buffer: ByteBuffer, ip: Packet.Ip4) {
        val udp = Packet.parseUdp(buffer, ip) ?: return
        if (udp.destPort != 53) return // only DNS for now
        val payload = ByteArray(udp.payloadLength)
        val pos = buffer.position()
        buffer.position(udp.payloadOffset)
        buffer.get(payload)
        buffer.position(pos)

        executor.execute {
            try {
                DatagramSocket().use { socket ->
                    vpnService.protect(socket)
                    socket.soTimeout = 5_000
                    val request =
                        DatagramPacket(
                            payload,
                            payload.size,
                            InetSocketAddress(dnsUpstream, 53),
                        )
                    socket.send(request)
                    val responseBuf = ByteArray(4096)
                    val response = DatagramPacket(responseBuf, responseBuf.size)
                    socket.receive(response)
                    val bytes = response.data.copyOf(response.length)
                    enqueuePacket(
                        Packet.buildIp4Udp(
                            source = ip.destination,
                            destination = ip.source,
                            sourcePort = 53,
                            destPort = udp.sourcePort,
                            payload = bytes,
                        ),
                    )
                }
            } catch (error: Exception) {
                Log.w(TAG, "DNS forward failed: ${error.message}")
            }
        }
    }

    private fun enqueueAck(session: TcpSession) {
        enqueuePacket(
            Packet.buildIp4Tcp(
                source = session.remoteIp,
                destination = session.clientIp,
                sourcePort = session.remotePort,
                destPort = session.clientPort,
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
            // Drop oldest to make room under pressure.
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
