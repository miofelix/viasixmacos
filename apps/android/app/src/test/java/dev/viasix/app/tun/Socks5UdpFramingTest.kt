package dev.viasix.app.tun

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.net.InetAddress

/**
 * Exercises real [Socks5UdpFraming] wrap/unwrap against RFC 1928 layouts.
 */
class Socks5UdpFramingTest {
    @Test
    fun wrapUnwrap_ipv4_roundTrip() {
        val remote = InetAddress.getByName("1.2.3.4")
        val payload = byteArrayOf(0xde.toByte(), 0xad.toByte(), 0xbe.toByte(), 0xef.toByte())
        val framed = Socks5UdpFraming.wrap(remote, 443, payload)

        // RSV RSV FRAG ATYP + 4 addr + 2 port + payload
        assertEquals(4 + 4 + 2 + payload.size, framed.size)
        assertEquals(0x00.toByte(), framed[0])
        assertEquals(0x00.toByte(), framed[1])
        assertEquals(0x00.toByte(), framed[2])
        assertEquals(Socks5UdpFraming.ATYP_IPV4.toByte(), framed[3])
        assertEquals(1.toByte(), framed[4])
        assertEquals(2.toByte(), framed[5])
        assertEquals(3.toByte(), framed[6])
        assertEquals(4.toByte(), framed[7])
        assertEquals(0x01.toByte(), framed[8]) // port 443
        assertEquals(0xbb.toByte(), framed[9])

        val parsed = Socks5UdpFraming.unwrap(framed)
        assertNotNull(parsed)
        assertEquals(remote, parsed!!.remote)
        assertEquals(443, parsed.remotePort)
        assertArrayEquals(payload, parsed.payload)
    }

    @Test
    fun wrapUnwrap_ipv6_roundTrip() {
        val remote = InetAddress.getByName("2001:db8::1")
        val payload = "hello-udp".toByteArray()
        val framed = Socks5UdpFraming.wrap(remote, 53, payload)
        assertEquals(Socks5UdpFraming.ATYP_IPV6.toByte(), framed[3])
        assertEquals(4 + 16 + 2 + payload.size, framed.size)

        val parsed = Socks5UdpFraming.unwrap(framed)
        assertNotNull(parsed)
        assertEquals(remote, parsed!!.remote)
        assertEquals(53, parsed.remotePort)
        assertArrayEquals(payload, parsed.payload)
    }

    @Test
    fun unwrap_rejectsFragmented() {
        val remote = InetAddress.getByName("8.8.8.8")
        val framed = Socks5UdpFraming.wrap(remote, 53, byteArrayOf(1, 2, 3))
        framed[2] = 0x01 // FRAG != 0
        assertNull(Socks5UdpFraming.unwrap(framed))
    }

    @Test
    fun unwrap_truncatedReturnsNull() {
        assertNull(Socks5UdpFraming.unwrap(byteArrayOf(0, 0, 0)))
        assertNull(Socks5UdpFraming.unwrap(byteArrayOf(0, 0, 0, 1, 1, 2, 3))) // missing port
    }

    @Test
    fun wrap_generalUdpPortNotOnlyDns() {
        // Production path must frame arbitrary UDP (QUIC 443, etc.), not only 53.
        val remote = InetAddress.getByName("104.16.0.1")
        val framed = Socks5UdpFraming.wrap(remote, 443, byteArrayOf(0x00))
        val parsed = Socks5UdpFraming.unwrap(framed)!!
        assertEquals(443, parsed.remotePort)
        assertEquals(remote, parsed.remote)
    }
}
