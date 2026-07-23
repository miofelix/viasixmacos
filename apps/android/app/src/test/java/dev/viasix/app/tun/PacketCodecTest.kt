package dev.viasix.app.tun

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress
import java.nio.ByteBuffer

/**
 * Drives real [Packet] builders/parsers for IPv4 and IPv6 TCP/UDP used by Tun2SocksEngine.
 */
class PacketCodecTest {
    private val client4 = InetAddress.getByName("10.10.0.2")
    private val remote4 = InetAddress.getByName("93.184.216.34")
    private val client6 = InetAddress.getByName("fd00:10:10::2")
    private val remote6 = InetAddress.getByName("2001:db8::1")

    @Test
    fun ipv4Udp_roundTrip_generalPort() {
        val payload = byteArrayOf(0x01, 0x02, 0x03, 0x04)
        val bytes =
            Packet.buildIp4Udp(
                source = remote4,
                destination = client4,
                sourcePort = 443,
                destPort = 54321,
                payload = payload,
            )
        val buf = ByteBuffer.wrap(bytes)
        assertEquals(4, Packet.ipVersion(buf))
        val ip = Packet.parseIp4(buf)!!
        assertEquals(Packet.PROTO_UDP.toInt(), ip.protocol)
        assertEquals(remote4, ip.source)
        assertEquals(client4, ip.destination)
        val udp = Packet.parseUdp(buf, ip)!!
        assertEquals(443, udp.sourcePort)
        assertEquals(54321, udp.destPort)
        assertEquals(payload.size, udp.payloadLength)
        val got = ByteArray(udp.payloadLength)
        buf.position(udp.payloadOffset)
        buf.get(got)
        assertArrayEquals(payload, got)
    }

    @Test
    fun ipv4Tcp_synAck_roundTrip() {
        val bytes =
            Packet.buildIp4Tcp(
                source = remote4,
                destination = client4,
                sourcePort = 443,
                destPort = 40000,
                seq = 1000L,
                ack = 2001L,
                flags = Packet.SYN or Packet.ACK,
                payload = ByteArray(0),
            )
        val buf = ByteBuffer.wrap(bytes)
        val ip = Packet.parseIp4(buf)!!
        val tcp = Packet.parseTcp(buf, ip)!!
        assertEquals(443, tcp.sourcePort)
        assertEquals(40000, tcp.destPort)
        assertEquals(1000L, tcp.seq)
        assertEquals(2001L, tcp.ack)
        assertEquals(Packet.SYN or Packet.ACK, tcp.flags and (Packet.SYN or Packet.ACK))
        assertEquals(65_535, tcp.window)
        assertEquals(0, tcp.payloadLength)
        // IP header checksum non-zero (computed)
        assertTrue(bytes[10].toInt() != 0 || bytes[11].toInt() != 0)
    }

    @Test
    fun ipv6Udp_roundTrip() {
        val payload = "quic".toByteArray()
        val bytes =
            Packet.buildIp6Udp(
                source = remote6,
                destination = client6,
                sourcePort = 443,
                destPort = 12345,
                payload = payload,
            )
        val buf = ByteBuffer.wrap(bytes)
        assertEquals(6, Packet.ipVersion(buf))
        val ip = Packet.parseIp6(buf)!!
        assertEquals(Packet.PROTO_UDP.toInt(), ip.nextHeader)
        assertEquals(remote6, ip.source)
        assertEquals(client6, ip.destination)
        val udp = Packet.parseUdp(buf, ip)!!
        assertEquals(443, udp.sourcePort)
        assertEquals(12345, udp.destPort)
        val got = ByteArray(udp.payloadLength)
        buf.position(udp.payloadOffset)
        buf.get(got)
        assertArrayEquals(payload, got)
        // IPv6 UDP checksum is mandatory and must be non-zero
        val csumOff = Packet.IP6_HEADER_SIZE + 6
        assertTrue(bytes[csumOff].toInt() != 0 || bytes[csumOff + 1].toInt() != 0)
    }

    @Test
    fun ipv6Tcp_roundTrip() {
        val payload = "GET /".toByteArray()
        val bytes =
            Packet.buildIp6Tcp(
                source = remote6,
                destination = client6,
                sourcePort = 80,
                destPort = 3333,
                seq = 42L,
                ack = 7L,
                flags = Packet.PSH or Packet.ACK,
                payload = payload,
            )
        val buf = ByteBuffer.wrap(bytes)
        val ip = Packet.parseIp6(buf)!!
        assertEquals(Packet.PROTO_TCP.toInt(), ip.nextHeader)
        val tcp = Packet.parseTcp(buf, ip)!!
        assertEquals(80, tcp.sourcePort)
        assertEquals(3333, tcp.destPort)
        assertEquals(42L, tcp.seq)
        assertEquals(7L, tcp.ack)
        assertEquals(65_535, tcp.window)
        assertEquals(payload.size, tcp.payloadLength)
        val got = ByteArray(tcp.payloadLength)
        buf.position(tcp.payloadOffset)
        buf.get(got)
        assertArrayEquals(payload, got)
    }

    @Test
    fun ipVersion_detectsBothFamilies() {
        val v4 = Packet.buildIp4Udp(client4, remote4, 1, 2, byteArrayOf(0))
        val v6 = Packet.buildIp6Udp(client6, remote6, 1, 2, byteArrayOf(0))
        assertEquals(4, Packet.ipVersion(ByteBuffer.wrap(v4)))
        assertEquals(6, Packet.ipVersion(ByteBuffer.wrap(v6)))
        assertEquals(-1, Packet.ipVersion(ByteBuffer.allocate(0)))
    }

    @Test
    fun parseIp4_rejectsIpv6Bytes() {
        val v6 = Packet.buildIp6Udp(client6, remote6, 1, 2, byteArrayOf(9))
        assertEquals(null, Packet.parseIp4(ByteBuffer.wrap(v6)))
        assertNotNull(Packet.parseIp6(ByteBuffer.wrap(v6)))
    }
}
