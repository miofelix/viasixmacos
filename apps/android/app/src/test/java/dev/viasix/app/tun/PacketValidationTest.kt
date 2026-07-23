package dev.viasix.app.tun

import org.junit.Assert.assertNull
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class PacketValidationTest {
    @Test
    fun rejectsIpPacketsWhoseDeclaredLengthExceedsTunFrame() {
        val ipv4 = ByteBuffer.allocate(Packet.IP4_HEADER_SIZE).order(ByteOrder.BIG_ENDIAN)
        ipv4.put(0, 0x45.toByte())
        ipv4.putShort(2, 60.toShort())

        val ipv6 = ByteBuffer.allocate(Packet.IP6_HEADER_SIZE).order(ByteOrder.BIG_ENDIAN)
        ipv6.put(0, 0x60.toByte())
        ipv6.putShort(4, 20.toShort())

        assertNull(Packet.parseIp4(ipv4))
        assertNull(Packet.parseIp6(ipv6))
    }

    @Test
    fun rejectsTransportLengthsAndHeaderOffsetsBeyondFrame() {
        val tcp = ByteBuffer.allocate(Packet.TCP_HEADER_SIZE).order(ByteOrder.BIG_ENDIAN)
        tcp.put(12, 0xf0.toByte())
        val udp = ByteBuffer.allocate(Packet.UDP_HEADER_SIZE).order(ByteOrder.BIG_ENDIAN)
        udp.putShort(4, 20.toShort())

        assertNull(Packet.parseTcp(tcp, payloadOffset = 0, l4Length = 40))
        assertNull(Packet.parseTcp(tcp, payloadOffset = 0, l4Length = Packet.TCP_HEADER_SIZE))
        assertNull(Packet.parseUdp(udp, payloadOffset = 0, l4Length = Packet.UDP_HEADER_SIZE))
    }
}
