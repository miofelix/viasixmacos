package dev.viasix.app.tun

import java.net.InetAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * IPv4/IPv6 packet helpers for the userspace TCP/UDP forwarder.
 */
internal object Packet {
    const val IP4_HEADER_SIZE = 20
    const val IP6_HEADER_SIZE = 40
    const val TCP_HEADER_SIZE = 20
    const val UDP_HEADER_SIZE = 8

    const val PROTO_TCP: Byte = 6
    const val PROTO_UDP: Byte = 17

    // TCP flags
    const val FIN = 0x01
    const val SYN = 0x02
    const val RST = 0x04
    const val PSH = 0x08
    const val ACK = 0x10

    data class Ip4(
        val versionIhl: Int,
        val totalLength: Int,
        val protocol: Int,
        val source: InetAddress,
        val destination: InetAddress,
        val headerLength: Int,
        val payloadOffset: Int,
    )

    data class Ip6(
        val payloadLength: Int,
        val nextHeader: Int,
        val source: InetAddress,
        val destination: InetAddress,
        val headerLength: Int = IP6_HEADER_SIZE,
        val payloadOffset: Int,
    )

    data class Tcp(
        val sourcePort: Int,
        val destPort: Int,
        val seq: Long,
        val ack: Long,
        val dataOffset: Int,
        val flags: Int,
        val payloadOffset: Int,
        val payloadLength: Int,
    )

    data class Udp(
        val sourcePort: Int,
        val destPort: Int,
        val length: Int,
        val payloadOffset: Int,
        val payloadLength: Int,
    )

    /** Returns 4, 6, or -1. */
    fun ipVersion(buffer: ByteBuffer): Int {
        if (buffer.remaining() < 1) return -1
        return (buffer.get(buffer.position()).toInt() and 0xf0) ushr 4
    }

    fun parseIp4(buffer: ByteBuffer): Ip4? {
        if (buffer.remaining() < IP4_HEADER_SIZE) return null
        val start = buffer.position()
        val versionIhl = buffer.get(start).toInt() and 0xff
        val version = versionIhl ushr 4
        if (version != 4) return null
        val ihl = (versionIhl and 0x0f) * 4
        if (ihl < IP4_HEADER_SIZE || buffer.remaining() < ihl) return null
        val totalLength = buffer.getShort(start + 2).toInt() and 0xffff
        if (totalLength < ihl || totalLength > buffer.limit() - start) return null
        val protocol = buffer.get(start + 9).toInt() and 0xff
        val src = ByteArray(4)
        val dst = ByteArray(4)
        buffer.position(start + 12)
        buffer.get(src)
        buffer.get(dst)
        buffer.position(start)
        return Ip4(
            versionIhl = versionIhl,
            totalLength = totalLength,
            protocol = protocol,
            source = InetAddress.getByAddress(src),
            destination = InetAddress.getByAddress(dst),
            headerLength = ihl,
            payloadOffset = start + ihl,
        )
    }

    fun parseIp6(buffer: ByteBuffer): Ip6? {
        if (buffer.remaining() < IP6_HEADER_SIZE) return null
        val start = buffer.position()
        val version = (buffer.get(start).toInt() and 0xf0) ushr 4
        if (version != 6) return null
        val payloadLength = buffer.getShort(start + 4).toInt() and 0xffff
        if (IP6_HEADER_SIZE + payloadLength > buffer.limit() - start) return null
        val nextHeader = buffer.get(start + 6).toInt() and 0xff
        // Extension headers are not walked — only direct TCP/UDP next-header.
        val src = ByteArray(16)
        val dst = ByteArray(16)
        buffer.position(start + 8)
        buffer.get(src)
        buffer.get(dst)
        buffer.position(start)
        return Ip6(
            payloadLength = payloadLength,
            nextHeader = nextHeader,
            source = InetAddress.getByAddress(src),
            destination = InetAddress.getByAddress(dst),
            payloadOffset = start + IP6_HEADER_SIZE,
        )
    }

    fun parseTcp(buffer: ByteBuffer, payloadOffset: Int, l4Length: Int): Tcp? {
        if (l4Length < TCP_HEADER_SIZE || buffer.limit() - payloadOffset < l4Length) return null
        val start = payloadOffset
        val sourcePort = buffer.getShort(start).toInt() and 0xffff
        val destPort = buffer.getShort(start + 2).toInt() and 0xffff
        val seq = buffer.getInt(start + 4).toLong() and 0xffffffffL
        val ack = buffer.getInt(start + 8).toLong() and 0xffffffffL
        val dataOffset = ((buffer.get(start + 12).toInt() and 0xf0) ushr 4) * 4
        if (dataOffset < TCP_HEADER_SIZE || dataOffset > l4Length) return null
        val flags = buffer.get(start + 13).toInt() and 0xff
        val tcpPayloadOffset = start + dataOffset
        val payloadLength = l4Length - dataOffset
        return Tcp(sourcePort, destPort, seq, ack, dataOffset, flags, tcpPayloadOffset, payloadLength)
    }

    fun parseTcp(buffer: ByteBuffer, ip: Ip4): Tcp? =
        parseTcp(buffer, ip.payloadOffset, ip.totalLength - ip.headerLength)

    fun parseTcp(buffer: ByteBuffer, ip: Ip6): Tcp? =
        parseTcp(buffer, ip.payloadOffset, ip.payloadLength)

    fun parseUdp(buffer: ByteBuffer, payloadOffset: Int, l4Length: Int): Udp? {
        if (l4Length < UDP_HEADER_SIZE || buffer.limit() - payloadOffset < l4Length) return null
        val start = payloadOffset
        val sourcePort = buffer.getShort(start).toInt() and 0xffff
        val destPort = buffer.getShort(start + 2).toInt() and 0xffff
        val length = buffer.getShort(start + 4).toInt() and 0xffff
        if (length < UDP_HEADER_SIZE || length > l4Length) return null
        val udpPayloadOffset = start + UDP_HEADER_SIZE
        val payloadLength = length - UDP_HEADER_SIZE
        return Udp(sourcePort, destPort, length, udpPayloadOffset, payloadLength)
    }

    fun parseUdp(buffer: ByteBuffer, ip: Ip4): Udp? =
        parseUdp(buffer, ip.payloadOffset, ip.totalLength - ip.headerLength)

    fun parseUdp(buffer: ByteBuffer, ip: Ip6): Udp? =
        parseUdp(buffer, ip.payloadOffset, ip.payloadLength)

    fun buildIp4Tcp(
        source: InetAddress,
        destination: InetAddress,
        sourcePort: Int,
        destPort: Int,
        seq: Long,
        ack: Long,
        flags: Int,
        payload: ByteArray,
    ): ByteArray {
        val total = IP4_HEADER_SIZE + TCP_HEADER_SIZE + payload.size
        val buf = ByteBuffer.allocate(total).order(ByteOrder.BIG_ENDIAN)
        buf.put(0x45.toByte())
        buf.put(0)
        buf.putShort(total.toShort())
        buf.putShort(0) // id
        buf.putShort(0x4000.toShort()) // don't fragment
        buf.put(64) // ttl
        buf.put(PROTO_TCP)
        buf.putShort(0) // checksum placeholder
        buf.put(source.address)
        buf.put(destination.address)
        buf.putShort(sourcePort.toShort())
        buf.putShort(destPort.toShort())
        buf.putInt(seq.toInt())
        buf.putInt(ack.toInt())
        buf.put(((5 shl 4).toByte())) // data offset = 5
        buf.put(flags.toByte())
        buf.putShort(0xffff.toShort()) // window
        buf.putShort(0) // checksum
        buf.putShort(0) // urgent
        if (payload.isNotEmpty()) buf.put(payload)

        val bytes = buf.array()
        writeChecksum(bytes, 10, ipChecksum(bytes, 0, IP4_HEADER_SIZE))
        writeChecksum(
            bytes,
            IP4_HEADER_SIZE + 16,
            transportChecksum(
                bytes,
                source.address,
                destination.address,
                PROTO_TCP.toInt(),
                IP4_HEADER_SIZE,
                TCP_HEADER_SIZE + payload.size,
            ),
        )
        return bytes
    }

    fun buildIp4Udp(
        source: InetAddress,
        destination: InetAddress,
        sourcePort: Int,
        destPort: Int,
        payload: ByteArray,
    ): ByteArray {
        val udpLen = UDP_HEADER_SIZE + payload.size
        val total = IP4_HEADER_SIZE + udpLen
        val buf = ByteBuffer.allocate(total).order(ByteOrder.BIG_ENDIAN)
        buf.put(0x45.toByte())
        buf.put(0)
        buf.putShort(total.toShort())
        buf.putShort(0)
        buf.putShort(0x4000.toShort())
        buf.put(64)
        buf.put(PROTO_UDP)
        buf.putShort(0)
        buf.put(source.address)
        buf.put(destination.address)
        buf.putShort(sourcePort.toShort())
        buf.putShort(destPort.toShort())
        buf.putShort(udpLen.toShort())
        buf.putShort(0)
        buf.put(payload)
        val bytes = buf.array()
        writeChecksum(bytes, 10, ipChecksum(bytes, 0, IP4_HEADER_SIZE))
        // UDP checksum optional for IPv4; leave 0.
        return bytes
    }

    fun buildIp6Tcp(
        source: InetAddress,
        destination: InetAddress,
        sourcePort: Int,
        destPort: Int,
        seq: Long,
        ack: Long,
        flags: Int,
        payload: ByteArray,
    ): ByteArray {
        val l4Len = TCP_HEADER_SIZE + payload.size
        val total = IP6_HEADER_SIZE + l4Len
        val buf = ByteBuffer.allocate(total).order(ByteOrder.BIG_ENDIAN)
        // version=6, traffic class=0, flow label=0
        buf.putInt(0x60000000)
        buf.putShort(l4Len.toShort())
        buf.put(PROTO_TCP)
        buf.put(64) // hop limit
        buf.put(source.address)
        buf.put(destination.address)
        buf.putShort(sourcePort.toShort())
        buf.putShort(destPort.toShort())
        buf.putInt(seq.toInt())
        buf.putInt(ack.toInt())
        buf.put(((5 shl 4).toByte()))
        buf.put(flags.toByte())
        buf.putShort(0xffff.toShort())
        buf.putShort(0)
        buf.putShort(0)
        if (payload.isNotEmpty()) buf.put(payload)
        val bytes = buf.array()
        writeChecksum(
            bytes,
            IP6_HEADER_SIZE + 16,
            transportChecksum(
                bytes,
                source.address,
                destination.address,
                PROTO_TCP.toInt(),
                IP6_HEADER_SIZE,
                l4Len,
            ),
        )
        return bytes
    }

    fun buildIp6Udp(
        source: InetAddress,
        destination: InetAddress,
        sourcePort: Int,
        destPort: Int,
        payload: ByteArray,
    ): ByteArray {
        val udpLen = UDP_HEADER_SIZE + payload.size
        val total = IP6_HEADER_SIZE + udpLen
        val buf = ByteBuffer.allocate(total).order(ByteOrder.BIG_ENDIAN)
        buf.putInt(0x60000000)
        buf.putShort(udpLen.toShort())
        buf.put(PROTO_UDP)
        buf.put(64)
        buf.put(source.address)
        buf.put(destination.address)
        buf.putShort(sourcePort.toShort())
        buf.putShort(destPort.toShort())
        buf.putShort(udpLen.toShort())
        buf.putShort(0)
        buf.put(payload)
        val bytes = buf.array()
        // UDP checksum is mandatory for IPv6
        writeChecksum(
            bytes,
            IP6_HEADER_SIZE + 6,
            transportChecksum(
                bytes,
                source.address,
                destination.address,
                PROTO_UDP.toInt(),
                IP6_HEADER_SIZE,
                udpLen,
            ).let { if (it == 0) 0xffff else it },
        )
        return bytes
    }

    private fun writeChecksum(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = ((value ushr 8) and 0xff).toByte()
        bytes[offset + 1] = (value and 0xff).toByte()
    }

    private fun ipChecksum(buf: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        val end = offset + length
        while (i + 1 < end) {
            sum += ((buf[i].toInt() and 0xff) shl 8) or (buf[i + 1].toInt() and 0xff)
            i += 2
        }
        if (i < end) sum += (buf[i].toInt() and 0xff) shl 8
        while (sum ushr 16 != 0) sum = (sum and 0xffff) + (sum ushr 16)
        return sum.inv() and 0xffff
    }

    /**
     * TCP/UDP checksum with IPv4 or IPv6 pseudo-header.
     */
    private fun transportChecksum(
        packet: ByteArray,
        src: ByteArray,
        dst: ByteArray,
        protocol: Int,
        transportOffset: Int,
        transportLength: Int,
    ): Int {
        var sum = 0
        // pseudo-header addresses
        var i = 0
        while (i + 1 < src.size) {
            sum += ((src[i].toInt() and 0xff) shl 8) or (src[i + 1].toInt() and 0xff)
            i += 2
        }
        i = 0
        while (i + 1 < dst.size) {
            sum += ((dst[i].toInt() and 0xff) shl 8) or (dst[i + 1].toInt() and 0xff)
            i += 2
        }
        if (src.size == 16) {
            // IPv6: upper-layer packet length as 32-bit big-endian
            sum += (transportLength ushr 16) and 0xffff
            sum += transportLength and 0xffff
            sum += protocol and 0xff
        } else {
            // IPv4: zero + protocol + length (16-bit)
            sum += protocol and 0xff
            sum += transportLength
        }
        i = transportOffset
        val end = transportOffset + transportLength
        while (i + 1 < end) {
            sum += ((packet[i].toInt() and 0xff) shl 8) or (packet[i + 1].toInt() and 0xff)
            i += 2
        }
        if (i < end) sum += (packet[i].toInt() and 0xff) shl 8
        while (sum ushr 16 != 0) sum = (sum and 0xffff) + (sum ushr 16)
        return sum.inv() and 0xffff
    }
}
