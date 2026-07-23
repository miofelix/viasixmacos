package dev.viasix.app.tun

import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Long-lived SOCKS5 UDP ASSOCIATE relay against a mixed/SOCKS port (e.g. mihomo).
 * Control TCP stays open for the lifetime of the associate; UDP payloads use [Socks5UdpFraming].
 */
internal class Socks5UdpRelay private constructor(
    private val control: Socket,
    private val udp: DatagramSocket,
    private val relayAddress: InetSocketAddress,
) : AutoCloseable {
    private val open = AtomicBoolean(true)

    val isOpen: Boolean
        get() = open.get() && !control.isClosed && !udp.isClosed

    fun send(remote: InetAddress, remotePort: Int, payload: ByteArray) {
        if (!isOpen) throw IOException("UDP relay closed")
        val framed = Socks5UdpFraming.wrap(remote, remotePort, payload)
        val packet = DatagramPacket(framed, framed.size, relayAddress)
        udp.send(packet)
    }

    /**
     * Blocking receive with optional timeout (ms). Returns null on timeout.
     */
    fun receive(timeoutMs: Int = 200): Socks5UdpFraming.Datagram? {
        if (!isOpen) return null
        udp.soTimeout = timeoutMs
        val buf = ByteArray(65535)
        val packet = DatagramPacket(buf, buf.size)
        return try {
            udp.receive(packet)
            Socks5UdpFraming.unwrap(packet.data, packet.length)
        } catch (_: SocketTimeoutException) {
            null
        }
    }

    override fun close() {
        if (!open.compareAndSet(true, false)) return
        try {
            udp.close()
        } catch (_: Exception) {
        }
        try {
            control.close()
        } catch (_: Exception) {
        }
    }

    companion object {
        /**
         * Open a UDP ASSOCIATE to [proxyHost]:[proxyPort].
         * Optional [protect] is invoked on the control TCP and UDP sockets (Android VpnService).
         */
        fun open(
            proxyHost: String,
            proxyPort: Int,
            connectTimeoutMs: Int = 10_000,
            protect: ((Socket) -> Boolean)? = null,
            protectDatagram: ((DatagramSocket) -> Boolean)? = null,
        ): Socks5UdpRelay {
            val control = Socket()
            control.tcpNoDelay = true
            control.connect(InetSocketAddress(proxyHost, proxyPort), connectTimeoutMs)
            protect?.invoke(control)

            val out = control.getOutputStream()
            val input = control.getInputStream()

            // greeting
            out.write(byteArrayOf(0x05, 0x01, 0x00))
            out.flush()
            val greet = readFully(input, 2)
            if (greet[0] != 0x05.toByte() || greet[1] != 0x00.toByte()) {
                control.close()
                throw IOException("SOCKS5 greeting rejected for UDP ASSOCIATE")
            }

            // UDP ASSOCIATE to 0.0.0.0:0 — proxy assigns BND
            out.write(
                byteArrayOf(
                    0x05,
                    0x03, // UDP ASSOCIATE
                    0x00,
                    0x01, // IPv4
                    0x00,
                    0x00,
                    0x00,
                    0x00,
                    0x00,
                    0x00,
                ),
            )
            out.flush()

            val head = readFully(input, 4)
            if (head[0] != 0x05.toByte() || head[1] != 0x00.toByte()) {
                control.close()
                throw IOException("SOCKS5 UDP ASSOCIATE failed status=${head[1]}")
            }
            val atyp = head[3].toInt() and 0xff
            val bindAddr: ByteArray
            val bindPort: Int
            when (atyp) {
                0x01 -> {
                    bindAddr = readFully(input, 4)
                    val p = readFully(input, 2)
                    bindPort = ((p[0].toInt() and 0xff) shl 8) or (p[1].toInt() and 0xff)
                }
                0x04 -> {
                    bindAddr = readFully(input, 16)
                    val p = readFully(input, 2)
                    bindPort = ((p[0].toInt() and 0xff) shl 8) or (p[1].toInt() and 0xff)
                }
                0x03 -> {
                    val len = readFully(input, 1)[0].toInt() and 0xff
                    val host = String(readFully(input, len), Charsets.US_ASCII)
                    val p = readFully(input, 2)
                    bindPort = ((p[0].toInt() and 0xff) shl 8) or (p[1].toInt() and 0xff)
                    val udp = DatagramSocket()
                    protectDatagram?.invoke(udp)
                    // Domain bind: resolve via the reported host (often 127.0.0.1 or proxy host).
                    val targetHost =
                        if (host == "0.0.0.0" || host.isEmpty()) proxyHost else host
                    val relay =
                        Socks5UdpRelay(
                            control,
                            udp,
                            InetSocketAddress(targetHost, bindPort),
                        )
                    return relay
                }
                else -> {
                    control.close()
                    throw IOException("SOCKS5 UDP ASSOCIATE unknown atyp=$atyp")
                }
            }

            val reported = InetAddress.getByAddress(bindAddr)
            // Many proxies return 0.0.0.0 — send to the proxy host instead.
            val hostForSend =
                if (
                    reported.isAnyLocalAddress ||
                        reported.hostAddress == "0.0.0.0" ||
                        reported.hostAddress == "::"
                ) {
                    InetAddress.getByName(proxyHost)
                } else {
                    reported
                }

            val udp = DatagramSocket()
            protectDatagram?.invoke(udp)
            return Socks5UdpRelay(
                control,
                udp,
                InetSocketAddress(hostForSend, bindPort),
            )
        }

        private fun readFully(input: java.io.InputStream, n: Int): ByteArray {
            val buf = ByteArray(n)
            var off = 0
            while (off < n) {
                val r = input.read(buf, off, n - off)
                if (r < 0) throw IOException("SOCKS5 EOF during UDP ASSOCIATE")
                off += r
            }
            return buf
        }
    }
}
