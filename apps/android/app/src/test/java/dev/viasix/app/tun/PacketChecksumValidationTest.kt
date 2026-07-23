package dev.viasix.app.tun

import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder

class PacketChecksumValidationTest {
    private val client4 = InetAddress.getByName("10.10.0.2")
    private val remote4 = InetAddress.getByName("93.184.216.34")
    private val client6 = InetAddress.getByName("fd00:10:10::2")
    private val remote6 = InetAddress.getByName("2001:db8::1")

    @Test
    fun rejectsCorruptedIpv4Header() {
        val packet = Packet.buildIp4Udp(client4, remote4, 53000, 53, byteArrayOf(1, 2, 3))
        packet[8] = (packet[8].toInt() xor 0x01).toByte()

        assertNull(Packet.parseIp4(ByteBuffer.wrap(packet)))
    }

    @Test
    fun rejectsCorruptedTcpPayloadForBothFamilies() {
        val ipv4 =
            Packet.buildIp4Tcp(
                client4,
                remote4,
                40000,
                443,
                10,
                20,
                Packet.ACK,
                byteArrayOf(1, 2, 3, 4),
            )
        val ip4 = Packet.parseIp4(ByteBuffer.wrap(ipv4))!!
        corruptLastByte(ipv4)
        assertNull(Packet.parseTcp(ByteBuffer.wrap(ipv4), ip4))

        val ipv6 =
            Packet.buildIp6Tcp(
                client6,
                remote6,
                40000,
                443,
                10,
                20,
                Packet.ACK,
                byteArrayOf(1, 2, 3, 4),
            )
        val ip6 = Packet.parseIp6(ByteBuffer.wrap(ipv6))!!
        corruptLastByte(ipv6)
        assertNull(Packet.parseTcp(ByteBuffer.wrap(ipv6), ip6))
    }

    @Test
    fun validatesUdpChecksumWithIpv4ZeroChecksumException() {
        val ipv4 = Packet.buildIp4Udp(client4, remote4, 53000, 53, byteArrayOf(1, 2, 3, 4))
        val ip4 = Packet.parseIp4(ByteBuffer.wrap(ipv4))!!
        val ipv4Checksum =
            ByteBuffer.wrap(ipv4).order(ByteOrder.BIG_ENDIAN)
                .getShort(Packet.IP4_HEADER_SIZE + 6).toInt() and 0xffff
        assertNotEquals(0, ipv4Checksum)
        corruptLastByte(ipv4)
        assertNull(Packet.parseUdp(ByteBuffer.wrap(ipv4), ip4))

        val uncheckedIpv4 =
            Packet.buildIp4Udp(client4, remote4, 53000, 53, byteArrayOf(1, 2, 3, 4))
        uncheckedIpv4[Packet.IP4_HEADER_SIZE + 6] = 0
        uncheckedIpv4[Packet.IP4_HEADER_SIZE + 7] = 0
        val uncheckedIp4 = Packet.parseIp4(ByteBuffer.wrap(uncheckedIpv4))!!
        assertNotNull(Packet.parseUdp(ByteBuffer.wrap(uncheckedIpv4), uncheckedIp4))

        val ipv6 = Packet.buildIp6Udp(client6, remote6, 53000, 53, byteArrayOf(1, 2, 3, 4))
        val ip6 = Packet.parseIp6(ByteBuffer.wrap(ipv6))!!
        ipv6[Packet.IP6_HEADER_SIZE + 6] = 0
        ipv6[Packet.IP6_HEADER_SIZE + 7] = 0
        assertNull(Packet.parseUdp(ByteBuffer.wrap(ipv6), ip6))
    }

    @Test
    fun rejectsUdpLengthThatDoesNotMatchIpPayload() {
        val udp = ByteBuffer.allocate(Packet.UDP_HEADER_SIZE + 4).order(ByteOrder.BIG_ENDIAN)
        udp.putShort(4, Packet.UDP_HEADER_SIZE.toShort())

        assertNull(Packet.parseUdp(udp, payloadOffset = 0, l4Length = udp.limit()))
    }

    @Test
    fun buildersRejectWrongAddressFamilyAndOversizedPayloads() {
        assertThrows(IllegalArgumentException::class.java) {
            Packet.buildIp4Udp(client6, remote6, 1, 2, byteArrayOf(1))
        }
        assertThrows(IllegalArgumentException::class.java) {
            Packet.buildIp4Udp(client4, remote4, 1, 2, ByteArray(65_508))
        }
        assertThrows(IllegalArgumentException::class.java) {
            Packet.buildIp6Tcp(client6, remote6, 1, 2, 0, 0, Packet.ACK, ByteArray(65_516))
        }
    }

    private fun corruptLastByte(packet: ByteArray) {
        packet[packet.lastIndex] = (packet.last().toInt() xor 0x01).toByte()
    }
}
