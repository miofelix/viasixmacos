package dev.viasix.app.tun

import java.io.IOException
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.LockSupport

/**
 * Long-lived SOCKS5 UDP ASSOCIATE relay against a mixed/SOCKS port (e.g. mihomo).
 * Control TCP stays open for the lifetime of the associate; UDP payloads use [Socks5UdpFraming].
 */
internal class Socks5UdpRelay private constructor(
    private val control: Socket,
    private val udp: DatagramChannel,
) : AutoCloseable {
    private val open = AtomicBoolean(true)
    private val receiveBuffer = ByteBuffer.allocate(MAX_PACKET_BYTES)

    val isOpen: Boolean
        get() = open.get() && !control.isClosed && udp.isOpen

    internal val selectableChannel: DatagramChannel
        get() = udp

    fun send(remote: InetAddress, remotePort: Int, payload: ByteArray) {
        if (!isOpen) throw IOException("UDP relay closed")
        val framed = Socks5UdpFraming.wrap(remote, remotePort, payload)
        val sent = udp.write(ByteBuffer.wrap(framed))
        if (sent != framed.size) throw IOException("SOCKS5 UDP relay send would block")
    }

    /**
     * Poll one available relay datagram without blocking.
     */
    internal fun receiveNow(): Socks5UdpFraming.Datagram? {
        if (!isOpen) return null
        return synchronized(receiveBuffer) {
            receiveBuffer.clear()
            val length = udp.read(receiveBuffer)
            if (length <= 0) return@synchronized null
            Socks5UdpFraming.unwrap(receiveBuffer.array(), length)
        }
    }

    /** Compatibility helper for bounded waits in lifecycle tests. */
    fun receive(timeoutMs: Int = 200): Socks5UdpFraming.Datagram? {
        val deadline = System.nanoTime() + timeoutMs.coerceAtLeast(0).toLong() * 1_000_000L
        while (isOpen) {
            receiveNow()?.let { return it }
            if (System.nanoTime() >= deadline) {
                if (!probeControlConnection()) {
                    throw IOException("SOCKS5 UDP control connection closed")
                }
                return null
            }
            LockSupport.parkNanos(RECEIVE_POLL_NANOS)
        }
        return null
    }

    internal fun probeControlConnection(): Boolean {
        val alive = controlConnectionAlive()
        if (!alive) close()
        return alive
    }

    /** SOCKS5 sends no control payload after ASSOCIATE, so timeout means alive and EOF means dead. */
    private fun controlConnectionAlive(): Boolean {
        if (control.isClosed) return false
        val previousTimeout =
            try {
                control.soTimeout
            } catch (_: Exception) {
                return false
            }
        return try {
            control.soTimeout = CONTROL_PROBE_TIMEOUT_MS
            control.getInputStream().read()
            false
        } catch (_: SocketTimeoutException) {
            true
        } catch (_: Exception) {
            false
        } finally {
            try {
                if (!control.isClosed) control.soTimeout = previousTimeout
            } catch (_: Exception) {
            }
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
            var udp: DatagramChannel? = null
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
                if (
                    head[0] != 0x05.toByte() ||
                        head[1] != 0x00.toByte() ||
                        head[2] != 0x00.toByte()
                ) {
                    throw IOException("SOCKS5 UDP ASSOCIATE failed status=${head[1]}")
                }
                val relayAddress = readRelayAddress(input, head[3].toInt() and 0xff, proxyHost)
                if (relayAddress.isUnresolved) {
                    throw IOException("SOCKS5 UDP relay address could not be resolved")
                }

                val datagram = DatagramChannel.open()
                udp = datagram
                datagram.bind(null)
                val datagramSocket = datagram.socket()
                if (protectDatagram?.invoke(datagramSocket) == false) {
                    throw IOException("VpnService.protect(SOCKS5 UDP socket) failed")
                }
                datagram.connect(relayAddress)
                datagram.configureBlocking(false)
                control.soTimeout = 0
                return Socks5UdpRelay(control, datagram).also { udp = null }
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
                        if (len == 0) throw IOException("SOCKS5 returned empty UDP relay domain")
                        val reported = String(readFully(input, len), Charsets.US_ASCII)
                        if (reported == "0.0.0.0" || reported == "::") {
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

        private const val CONTROL_PROBE_TIMEOUT_MS = 1
        private const val MAX_PACKET_BYTES = 65_535
        private const val RECEIVE_POLL_NANOS = 1_000_000L
    }
}
