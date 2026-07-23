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
            var udp: DatagramSocket? = null
            try {
                control.tcpNoDelay = true
                control.soTimeout = connectTimeoutMs
                if (protect?.invoke(control) == false) {
                    throw IOException("VpnService.protect(SOCKS5 UDP control) failed")
                }
                control.connect(InetSocketAddress(proxyHost, proxyPort), connectTimeoutMs)

                val out = control.getOutputStream()
                val input = control.getInputStream()

                // greeting
                out.write(byteArrayOf(0x05, 0x01, 0x00))
                out.flush()
                val greet = readFully(input, 2)
                if (greet[0] != 0x05.toByte() || greet[1] != 0x00.toByte()) {
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
                    throw IOException("SOCKS5 UDP ASSOCIATE failed status=${head[1]}")
                }
                val relayAddress = readRelayAddress(input, head[3].toInt() and 0xff, proxyHost)

                val datagram = DatagramSocket()
                udp = datagram
                if (protectDatagram?.invoke(datagram) == false) {
                    throw IOException("VpnService.protect(SOCKS5 UDP socket) failed")
                }
                control.soTimeout = 0
                return Socks5UdpRelay(control, datagram, relayAddress).also { udp = null }
            } catch (error: Exception) {
                try {
                    udp?.close()
                } catch (_: Exception) {
                }
                try {
                    control.close()
                } catch (_: Exception) {
                }
                throw error
            }
        }

        private fun readRelayAddress(
            input: java.io.InputStream,
            atyp: Int,
            proxyHost: String,
        ): InetSocketAddress {
            val host =
                when (atyp) {
                    0x01 -> reportedHost(readFully(input, 4), proxyHost)
                    0x04 -> reportedHost(readFully(input, 16), proxyHost)
                    0x03 -> {
                        val len = readFully(input, 1)[0].toInt() and 0xff
                        val reported = String(readFully(input, len), Charsets.US_ASCII)
                        if (reported.isEmpty() || reported == "0.0.0.0" || reported == "::") {
                            proxyHost
                        } else {
                            reported
                        }
                    }
                    else -> throw IOException("SOCKS5 UDP ASSOCIATE unknown atyp=$atyp")
                }
            val portBytes = readFully(input, 2)
            val port =
                ((portBytes[0].toInt() and 0xff) shl 8) or
                    (portBytes[1].toInt() and 0xff)
            if (port == 0) throw IOException("SOCKS5 UDP ASSOCIATE returned port 0")
            return InetSocketAddress(host, port)
        }

        private fun reportedHost(address: ByteArray, proxyHost: String): String {
            val reported = InetAddress.getByAddress(address)
            return if (reported.isAnyLocalAddress) proxyHost else reported.hostAddress
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
