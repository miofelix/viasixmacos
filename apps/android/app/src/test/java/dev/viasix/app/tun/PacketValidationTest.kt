package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.net.InetAddress
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

    @Test
    fun rejectsMalformedTcpMssOptions() {
        val packet =
            Packet.buildIp4Tcp(
                source = InetAddress.getByName("10.10.0.2"),
                destination = InetAddress.getByName("1.1.1.1"),
                sourcePort = 53_000,
                destPort = 443,
                seq = 1,
                ack = 2,
                flags = Packet.SYN,
                payload = ByteArray(0),
                maximumSegmentSize = 1_000,
            )
        packet[Packet.IP4_HEADER_SIZE + Packet.TCP_HEADER_SIZE + 1] = 3

        val buffer = ByteBuffer.wrap(packet)
        val ip = Packet.parseIp4(buffer)!!
        assertNull(Packet.parseTcp(buffer, ip.payloadOffset, ip.totalLength - ip.headerLength))
    }

    @Test
    fun clampsExcessiveWindowScaleAndRejectsDuplicates() {
        val packet =
            Packet.buildIp4Tcp(
                source = InetAddress.getByName("10.10.0.2"),
                destination = InetAddress.getByName("1.1.1.1"),
                sourcePort = 53_000,
                destPort = 443,
                seq = 1,
                ack = 2,
                flags = Packet.SYN,
                payload = ByteArray(0),
                maximumSegmentSize = 1_000,
                windowScale = 14,
            )
        packet[Packet.IP4_HEADER_SIZE + Packet.TCP_HEADER_SIZE + 7] = 30
        val packetBuffer = ByteBuffer.wrap(packet)
        val ip = Packet.parseIp4(packetBuffer)!!
        assertEquals(
            14,
            Packet.parseTcp(packetBuffer, ip.payloadOffset, ip.totalLength - ip.headerLength)?.windowScale,
        )

        val duplicate = ByteBuffer.allocate(28).order(ByteOrder.BIG_ENDIAN)
        duplicate.put(12, 0x70.toByte())
        duplicate.put(13, Packet.SYN.toByte())
        duplicate.position(Packet.TCP_HEADER_SIZE)
        duplicate.put(byteArrayOf(3, 3, 1, 1, 3, 3, 2, 0))
        assertNull(Packet.parseTcp(duplicate, payloadOffset = 0, l4Length = duplicate.capacity()))
    }

    @Test
    fun rejectsIpv4FragmentsThatRequireReassembly() {
        val base =
            Packet.buildIp4Udp(
                source = InetAddress.getByName("10.10.0.2"),
                destination = InetAddress.getByName("1.1.1.1"),
                sourcePort = 53000,
                destPort = 53,
                payload = byteArrayOf(1, 2, 3, 4),
            )
        val moreFragments = base.copyOf()
        val nonInitial = base.copyOf()
        val reserved = base.copyOf()
        ByteBuffer.wrap(moreFragments).order(ByteOrder.BIG_ENDIAN).putShort(6, 0x2000.toShort())
        ByteBuffer.wrap(nonInitial).order(ByteOrder.BIG_ENDIAN).putShort(6, 1)
        ByteBuffer.wrap(reserved).order(ByteOrder.BIG_ENDIAN).putShort(6, 0x8000.toShort())

        assertNull(Packet.parseIp4(ByteBuffer.wrap(moreFragments)))
        assertNull(Packet.parseIp4(ByteBuffer.wrap(nonInitial)))
        assertNull(Packet.parseIp4(ByteBuffer.wrap(reserved)))
    }

    @Test
    fun walksBoundedIpv6ExtensionHeadersToUdp() {
        val packet = ipv6UdpWithExtensions(extensionHeaders = intArrayOf(0, 43, 60))
        val buffer = ByteBuffer.wrap(packet)

        val ip = Packet.parseIp6(buffer)

        assertNotNull(ip)
        assertEquals(Packet.PROTO_UDP.toInt(), ip!!.nextHeader)
        assertEquals(Packet.IP6_HEADER_SIZE + 24, ip.headerLength)
        assertEquals(Packet.IP6_HEADER_SIZE + 24, ip.payloadOffset)
        assertNotNull(Packet.parseUdp(buffer, ip))

        val authenticated = ByteBuffer.wrap(ipv6UdpWithAuthenticationHeader())
        val authenticatedIp = Packet.parseIp6(authenticated)
        assertNotNull(authenticatedIp)
        assertEquals(Packet.IP6_HEADER_SIZE + 12, authenticatedIp!!.headerLength)
        assertNotNull(Packet.parseUdp(authenticated, authenticatedIp))
    }

    @Test
    fun acceptsAtomicIpv6FragmentButRejectsPacketsNeedingReassembly() {
        val atomic = ipv6UdpWithFragment(fragmentBits = 0)
        val moreFragments = ipv6UdpWithFragment(fragmentBits = 1)
        val reservedBits = ipv6UdpWithFragment(fragmentBits = 2)
        val nonInitial = ipv6UdpWithFragment(fragmentBits = 1 shl 3)

        val atomicIp = Packet.parseIp6(ByteBuffer.wrap(atomic))

        assertNotNull(atomicIp)
        assertEquals(Packet.PROTO_UDP.toInt(), atomicIp!!.nextHeader)
        assertNull(Packet.parseIp6(ByteBuffer.wrap(moreFragments)))
        assertNull(Packet.parseIp6(ByteBuffer.wrap(reservedBits)))
        assertNull(Packet.parseIp6(ByteBuffer.wrap(nonInitial)))
    }

    @Test
    fun rejectsTruncatedOrExcessiveIpv6ExtensionChains() {
        val truncated =
            ipv6UdpWithExtensions(extensionHeaders = intArrayOf(60))
                .copyOf(Packet.IP6_HEADER_SIZE + 8)
        ByteBuffer.wrap(truncated).order(ByteOrder.BIG_ENDIAN).putShort(4, 8)
        truncated[Packet.IP6_HEADER_SIZE + 1] = 1
        val excessive = ipv6UdpWithExtensions(extensionHeaders = IntArray(9) { 60 })

        assertNull(Packet.parseIp6(ByteBuffer.wrap(truncated)))
        assertNull(Packet.parseIp6(ByteBuffer.wrap(excessive)))
    }

    private fun ipv6UdpWithFragment(fragmentBits: Int): ByteArray {
        val packet = ipv6UdpWithExtensions(extensionHeaders = intArrayOf(44))
        ByteBuffer.wrap(packet).order(ByteOrder.BIG_ENDIAN).putShort(
            Packet.IP6_HEADER_SIZE + 2,
            fragmentBits.toShort(),
        )
        return packet
    }

    private fun ipv6UdpWithAuthenticationHeader(): ByteArray {
        val base = ipv6UdpWithExtensions(extensionHeaders = intArrayOf())
        val packet = ByteArray(base.size + 12)
        base.copyInto(packet, endIndex = Packet.IP6_HEADER_SIZE)
        ByteBuffer.wrap(packet).order(ByteOrder.BIG_ENDIAN).putShort(
            4,
            (base.size - Packet.IP6_HEADER_SIZE + 12).toShort(),
        )
        packet[6] = 51
        packet[Packet.IP6_HEADER_SIZE] = Packet.PROTO_UDP
        packet[Packet.IP6_HEADER_SIZE + 1] = 1
        base.copyInto(
            destination = packet,
            destinationOffset = Packet.IP6_HEADER_SIZE + 12,
            startIndex = Packet.IP6_HEADER_SIZE,
        )
        return packet
    }

    private fun ipv6UdpWithExtensions(extensionHeaders: IntArray): ByteArray {
        val source = InetAddress.getByName("2001:db8::1")
        val destination = InetAddress.getByName("fd00:10:10::2")
        val base =
            Packet.buildIp6Udp(
                source = source,
                destination = destination,
                sourcePort = 53,
                destPort = 53000,
                payload = byteArrayOf(1, 2, 3, 4),
            )
        val extensionBytes = extensionHeaders.size * 8
        val packet = ByteArray(base.size + extensionBytes)
        base.copyInto(packet, endIndex = Packet.IP6_HEADER_SIZE)
        ByteBuffer.wrap(packet).order(ByteOrder.BIG_ENDIAN).putShort(
            4,
            (base.size - Packet.IP6_HEADER_SIZE + extensionBytes).toShort(),
        )
        packet[6] =
            if (extensionHeaders.isEmpty()) {
                Packet.PROTO_UDP
            } else {
                extensionHeaders.first().toByte()
            }
        extensionHeaders.forEachIndexed { index, _ ->
            val offset = Packet.IP6_HEADER_SIZE + index * 8
            packet[offset] =
                if (index == extensionHeaders.lastIndex) {
                    Packet.PROTO_UDP
                } else {
                    extensionHeaders[index + 1].toByte()
                }
            packet[offset + 1] = 0
        }
        base.copyInto(
            destination = packet,
            destinationOffset = Packet.IP6_HEADER_SIZE + extensionBytes,
            startIndex = Packet.IP6_HEADER_SIZE,
        )
        return packet
    }
}
