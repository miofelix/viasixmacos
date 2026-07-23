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
        val window: Int,
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
        if (!checksumValid(buffer, start, ihl)) return null
        val fragmentBits = buffer.getShort(start + 6).toInt() and 0xffff
        val reservedFlag = fragmentBits and 0x8000 != 0
        val moreFragments = fragmentBits and 0x2000 != 0
        val fragmentOffset = fragmentBits and 0x1fff
        if (reservedFlag || moreFragments || fragmentOffset != 0) return null
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
        val declaredPayloadLength = buffer.getShort(start + 4).toInt() and 0xffff
        if (IP6_HEADER_SIZE + declaredPayloadLength > buffer.limit() - start) return null
        val frameEnd = start + IP6_HEADER_SIZE + declaredPayloadLength
        val src = ByteArray(16)
        val dst = ByteArray(16)
        buffer.position(start + 8)
        buffer.get(src)
        buffer.get(dst)
        buffer.position(start)

        var nextHeader = buffer.get(start + 6).toInt() and 0xff
        var payloadOffset = start + IP6_HEADER_SIZE
        var payloadLength = declaredPayloadLength
        var extensionCount = 0
        var sawFragment = false
        while (isIpv6ExtensionHeader(nextHeader)) {
            extensionCount += 1
            if (extensionCount > MAX_IPV6_EXTENSION_HEADERS) return null
            val extensionLength =
                when (nextHeader) {
                    IPV6_FRAGMENT -> {
                        if (sawFragment || payloadLength < IPV6_FRAGMENT_HEADER_SIZE) return null
                        val fragmentBits =
                            buffer.getShort(payloadOffset + 2).toInt() and 0xffff
                        val fragmentOffset = (fragmentBits and 0xfff8) ushr 3
                        val reservedBits = fragmentBits and 0x0006
                        val moreFragments = fragmentBits and 0x0001 != 0
                        if (fragmentOffset != 0 || reservedBits != 0 || moreFragments) return null
                        sawFragment = true
                        IPV6_FRAGMENT_HEADER_SIZE
                    }
                    IPV6_AUTHENTICATION -> {
                        if (payloadLength < IPV6_AUTHENTICATION_MIN_SIZE) return null
                        val length =
                            ((buffer.get(payloadOffset + 1).toInt() and 0xff) + 2) * 4
                        if (length < IPV6_AUTHENTICATION_MIN_SIZE) return null
                        length
                    }
                    else -> {
                        if (payloadLength < IPV6_EXTENSION_MIN_SIZE) return null
                        ((buffer.get(payloadOffset + 1).toInt() and 0xff) + 1) * 8
                    }
                }
            if (
                extensionLength > payloadLength ||
                    payloadOffset + extensionLength > frameEnd
            ) {
                return null
            }
            nextHeader = buffer.get(payloadOffset).toInt() and 0xff
            payloadOffset += extensionLength
            payloadLength -= extensionLength
        }
        return Ip6(
            payloadLength = payloadLength,
            nextHeader = nextHeader,
            source = InetAddress.getByAddress(src),
            destination = InetAddress.getByAddress(dst),
            headerLength = payloadOffset - start,
            payloadOffset = payloadOffset,
        )
    }

    private fun isIpv6ExtensionHeader(nextHeader: Int): Boolean =
        nextHeader == IPV6_HOP_BY_HOP ||
            nextHeader == IPV6_ROUTING ||
            nextHeader == IPV6_FRAGMENT ||
            nextHeader == IPV6_AUTHENTICATION ||
            nextHeader == IPV6_DESTINATION_OPTIONS

    fun parseTcp(buffer: ByteBuffer, payloadOffset: Int, l4Length: Int): Tcp? {
        if (
            payloadOffset < 0 ||
                l4Length < TCP_HEADER_SIZE ||
                payloadOffset > buffer.limit() - l4Length
        ) {
            return null
        }
        val start = payloadOffset
        val sourcePort = buffer.getShort(start).toInt() and 0xffff
        val destPort = buffer.getShort(start + 2).toInt() and 0xffff
        val seq = buffer.getInt(start + 4).toLong() and 0xffffffffL
        val ack = buffer.getInt(start + 8).toLong() and 0xffffffffL
        val dataOffset = ((buffer.get(start + 12).toInt() and 0xf0) ushr 4) * 4
        if (dataOffset < TCP_HEADER_SIZE || dataOffset > l4Length) return null
        val flags = buffer.get(start + 13).toInt() and 0xff
        val window = buffer.getShort(start + 14).toInt() and 0xffff
        val tcpPayloadOffset = start + dataOffset
        val payloadLength = l4Length - dataOffset
        return Tcp(
            sourcePort,
            destPort,
            seq,
            ack,
            dataOffset,
            flags,
            window,
            tcpPayloadOffset,
            payloadLength,
        )
    }

    fun parseTcp(buffer: ByteBuffer, ip: Ip4): Tcp? {
        if (ip.protocol != PROTO_TCP.toInt()) return null
        val l4Length = ip.totalLength - ip.headerLength
        val tcp = parseTcp(buffer, ip.payloadOffset, l4Length) ?: return null
        return if (
            transportChecksumValid(
                buffer,
                ip.source.address,
                ip.destination.address,
                PROTO_TCP.toInt(),
                ip.payloadOffset,
                l4Length,
            )
        ) {
            tcp
        } else {
            null
        }
    }

    fun parseTcp(buffer: ByteBuffer, ip: Ip6): Tcp? {
        if (ip.nextHeader != PROTO_TCP.toInt()) return null
        val tcp = parseTcp(buffer, ip.payloadOffset, ip.payloadLength) ?: return null
        return if (
            transportChecksumValid(
                buffer,
                ip.source.address,
                ip.destination.address,
                PROTO_TCP.toInt(),
                ip.payloadOffset,
                ip.payloadLength,
            )
        ) {
            tcp
        } else {
            null
        }
    }

    fun parseUdp(buffer: ByteBuffer, payloadOffset: Int, l4Length: Int): Udp? {
        if (
            payloadOffset < 0 ||
                l4Length < UDP_HEADER_SIZE ||
                payloadOffset > buffer.limit() - l4Length
        ) {
            return null
        }
        val start = payloadOffset
        val sourcePort = buffer.getShort(start).toInt() and 0xffff
        val destPort = buffer.getShort(start + 2).toInt() and 0xffff
        val length = buffer.getShort(start + 4).toInt() and 0xffff
        if (length < UDP_HEADER_SIZE || length != l4Length) return null
        val udpPayloadOffset = start + UDP_HEADER_SIZE
        val payloadLength = length - UDP_HEADER_SIZE
        return Udp(sourcePort, destPort, length, udpPayloadOffset, payloadLength)
    }

    fun parseUdp(buffer: ByteBuffer, ip: Ip4): Udp? {
        if (ip.protocol != PROTO_UDP.toInt()) return null
        val l4Length = ip.totalLength - ip.headerLength
        val udp = parseUdp(buffer, ip.payloadOffset, l4Length) ?: return null
        val checksum = buffer.getShort(ip.payloadOffset + 6).toInt() and 0xffff
        if (checksum == 0) return udp
        return if (
            transportChecksumValid(
                buffer,
                ip.source.address,
                ip.destination.address,
                PROTO_UDP.toInt(),
                ip.payloadOffset,
                l4Length,
            )
        ) {
            udp
        } else {
            null
        }
    }

    fun parseUdp(buffer: ByteBuffer, ip: Ip6): Udp? {
        if (ip.nextHeader != PROTO_UDP.toInt()) return null
        val udp = parseUdp(buffer, ip.payloadOffset, ip.payloadLength) ?: return null
        val checksum = buffer.getShort(ip.payloadOffset + 6).toInt() and 0xffff
        if (checksum == 0) return null
        return if (
            transportChecksumValid(
                buffer,
                ip.source.address,
                ip.destination.address,
                PROTO_UDP.toInt(),
                ip.payloadOffset,
                ip.payloadLength,
            )
        ) {
            udp
        } else {
            null
        }
    }

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
        requireBuildFields(source, destination, 4, sourcePort, destPort, MAX_IP4_TCP_PAYLOAD, payload)
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
        requireBuildFields(source, destination, 4, sourcePort, destPort, MAX_IP4_UDP_PAYLOAD, payload)
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
        writeChecksum(
            bytes,
            IP4_HEADER_SIZE + 6,
            transportChecksum(
                bytes,
                source.address,
                destination.address,
                PROTO_UDP.toInt(),
                IP4_HEADER_SIZE,
                udpLen,
            ).let { if (it == 0) 0xffff else it },
        )
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
        requireBuildFields(source, destination, 16, sourcePort, destPort, MAX_IP6_TCP_PAYLOAD, payload)
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
        requireBuildFields(source, destination, 16, sourcePort, destPort, MAX_IP6_UDP_PAYLOAD, payload)
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
        return foldChecksum(addBytes(0L, buf, offset, length)).inv() and 0xffff
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
        var sum = pseudoHeaderSum(src, dst, protocol, transportLength)
        sum = addBytes(sum, packet, transportOffset, transportLength)
        return foldChecksum(sum).inv() and 0xffff
    }

    private fun checksumValid(buffer: ByteBuffer, offset: Int, length: Int): Boolean =
        foldChecksum(addBuffer(0L, buffer, offset, length)) == 0xffff

    private fun transportChecksumValid(
        buffer: ByteBuffer,
        src: ByteArray,
        dst: ByteArray,
        protocol: Int,
        transportOffset: Int,
        transportLength: Int,
    ): Boolean {
        var sum = pseudoHeaderSum(src, dst, protocol, transportLength)
        sum = addBuffer(sum, buffer, transportOffset, transportLength)
        return foldChecksum(sum) == 0xffff
    }

    private fun pseudoHeaderSum(
        src: ByteArray,
        dst: ByteArray,
        protocol: Int,
        transportLength: Int,
    ): Long {
        var sum = addBytes(0L, src, 0, src.size)
        sum = addBytes(sum, dst, 0, dst.size)
        if (src.size == 16) {
            sum += (transportLength ushr 16) and 0xffff
            sum += transportLength and 0xffff
            sum += protocol and 0xff
        } else {
            sum += protocol and 0xff
            sum += transportLength
        }
        return sum
    }

    private fun addBytes(
        initial: Long,
        bytes: ByteArray,
        offset: Int,
        length: Int,
    ): Long {
        var sum = initial
        var index = offset
        val end = offset + length
        while (index + 1 < end) {
            sum +=
                ((bytes[index].toInt() and 0xff) shl 8) or
                    (bytes[index + 1].toInt() and 0xff)
            index += 2
        }
        if (index < end) sum += (bytes[index].toInt() and 0xff) shl 8
        return sum
    }

    private fun addBuffer(
        initial: Long,
        buffer: ByteBuffer,
        offset: Int,
        length: Int,
    ): Long {
        var sum = initial
        var index = offset
        val end = offset + length
        while (index + 1 < end) {
            sum +=
                ((buffer.get(index).toInt() and 0xff) shl 8) or
                    (buffer.get(index + 1).toInt() and 0xff)
            index += 2
        }
        if (index < end) sum += (buffer.get(index).toInt() and 0xff) shl 8
        return sum
    }

    private fun foldChecksum(value: Long): Int {
        var sum = value
        while (sum ushr 16 != 0L) {
            sum = (sum and 0xffffL) + (sum ushr 16)
        }
        return sum.toInt() and 0xffff
    }

    private fun requireBuildFields(
        source: InetAddress,
        destination: InetAddress,
        addressBytes: Int,
        sourcePort: Int,
        destPort: Int,
        maxPayload: Int,
        payload: ByteArray,
    ) {
        require(source.address.size == addressBytes && destination.address.size == addressBytes) {
            "source and destination must use the requested IP family"
        }
        require(sourcePort in 0..0xffff && destPort in 0..0xffff) {
            "ports must be unsigned 16-bit values"
        }
        require(payload.size <= maxPayload) { "payload exceeds IP packet length" }
    }

    private const val IPV6_HOP_BY_HOP = 0
    private const val IPV6_ROUTING = 43
    private const val IPV6_FRAGMENT = 44
    private const val IPV6_AUTHENTICATION = 51
    private const val IPV6_DESTINATION_OPTIONS = 60
    private const val IPV6_EXTENSION_MIN_SIZE = 8
    private const val IPV6_FRAGMENT_HEADER_SIZE = 8
    private const val IPV6_AUTHENTICATION_MIN_SIZE = 12
    private const val MAX_IPV6_EXTENSION_HEADERS = 8
    private const val MAX_IP4_TCP_PAYLOAD = 0xffff - IP4_HEADER_SIZE - TCP_HEADER_SIZE
    private const val MAX_IP6_TCP_PAYLOAD = 0xffff - TCP_HEADER_SIZE
    private const val MAX_IP4_UDP_PAYLOAD = 0xffff - IP4_HEADER_SIZE - UDP_HEADER_SIZE
    private const val MAX_IP6_UDP_PAYLOAD = 0xffff - UDP_HEADER_SIZE
}
