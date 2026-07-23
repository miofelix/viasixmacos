package dev.viasix.app.tun

import java.io.IOException
import java.io.InputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Minimal SOCKS5 CONNECT client used by the userspace TCP forwarder.
 */
internal object Socks5Client {
    fun connect(
        proxyHost: String,
        proxyPort: Int,
        targetHost: InetAddress,
        targetPort: Int,
        connectTimeoutMs: Int = 10_000,
        handshakeTimeoutMs: Int = 10_000,
    ): Socket {
        require(targetHost.address.size == 4 || targetHost.address.size == 16) {
            "SOCKS5 target must be IPv4 or IPv6"
        }
        require(targetPort in 1..0xffff) { "SOCKS5 target port must be 1..65535" }
        require(connectTimeoutMs >= 0 && handshakeTimeoutMs >= 0) {
            "SOCKS5 timeouts must not be negative"
        }
        val socket = Socket()
        try {
            socket.tcpNoDelay = true
            socket.soTimeout = handshakeTimeoutMs
            socket.connect(InetSocketAddress(proxyHost, proxyPort), connectTimeoutMs)
            val out = socket.getOutputStream()
            val input = socket.getInputStream()

            // greeting: ver=5, nmethods=1, method=0 (no auth)
            out.write(byteArrayOf(0x05, 0x01, 0x00))
            out.flush()
            val greet = readFully(input, 2)
            if (greet[0] != 0x05.toByte() || greet[1] != 0x00.toByte()) {
                throw IOException("SOCKS5 greeting rejected")
            }

            val addr = targetHost.address
            val req =
                ByteArray(4 + addr.size + 2).also { buf ->
                    buf[0] = 0x05
                    buf[1] = 0x01 // CONNECT
                    buf[2] = 0x00
                    buf[3] = if (addr.size == 4) 0x01 else 0x04
                    System.arraycopy(addr, 0, buf, 4, addr.size)
                    val portOff = 4 + addr.size
                    buf[portOff] = ((targetPort ushr 8) and 0xff).toByte()
                    buf[portOff + 1] = (targetPort and 0xff).toByte()
                }
            out.write(req)
            out.flush()

            val head = readFully(input, 4)
            if (
                head[0] != 0x05.toByte() ||
                    head[1] != 0x00.toByte() ||
                    head[2] != 0x00.toByte()
            ) {
                throw IOException("SOCKS5 connect failed status=${head[1]}")
            }
            val atyp = head[3].toInt() and 0xff
            when (atyp) {
                0x01 -> readFully(input, 4 + 2)
                0x03 -> {
                    val len = readFully(input, 1)[0].toInt() and 0xff
                    if (len == 0) throw IOException("SOCKS5 returned empty bind domain")
                    readFully(input, len + 2)
                }
                0x04 -> readFully(input, 16 + 2)
                else -> throw IOException("SOCKS5 unknown atyp=$atyp")
            }
            socket.soTimeout = 0
            return socket
        } catch (error: Exception) {
            try {
                socket.close()
            } catch (_: Exception) {
            }
            throw error
        }
    }

    private fun readFully(input: InputStream, n: Int): ByteArray {
        val buf = ByteArray(n)
        var off = 0
        while (off < n) {
            val r = input.read(buf, off, n - off)
            if (r < 0) throw IOException("SOCKS5 EOF")
            off += r
        }
        return buf
    }
}
