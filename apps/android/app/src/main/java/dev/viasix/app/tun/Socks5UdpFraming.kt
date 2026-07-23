package dev.viasix.app.tun

import java.net.InetAddress

/**
 * SOCKS5 UDP request/response framing (RFC 1928 §7).
 * Pure encode/decode — no sockets — for unit tests and the userspace relay.
 */
internal object Socks5UdpFraming {
    const val ATYP_IPV4: Int = 0x01
    const val ATYP_DOMAIN: Int = 0x03
    const val ATYP_IPV6: Int = 0x04

    data class Datagram(
        val remote: InetAddress,
        val remotePort: Int,
        val payload: ByteArray,
        val frag: Int = 0,
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Datagram) return false
            return remote == other.remote &&
                remotePort == other.remotePort &&
                frag == other.frag &&
                payload.contentEquals(other.payload)
        }

        override fun hashCode(): Int {
            var result = remote.hashCode()
            result = 31 * result + remotePort
            result = 31 * result + payload.contentHashCode()
            result = 31 * result + frag
            return result
        }
    }

    /**
     * Build a SOCKS5 UDP request header + payload for [remote]:[remotePort].
     * FRAG is always 0 (no fragmentation).
     */
    fun wrap(remote: InetAddress, remotePort: Int, payload: ByteArray): ByteArray {
        val addr = remote.address
        val atyp =
            when (addr.size) {
                4 -> ATYP_IPV4
                16 -> ATYP_IPV6
                else -> throw IllegalArgumentException("unsupported address length ${addr.size}")
            }
        val headerLen = 4 + addr.size + 2
        val out = ByteArray(headerLen + payload.size)
        out[0] = 0x00 // RSV
        out[1] = 0x00
        out[2] = 0x00 // FRAG
        out[3] = atyp.toByte()
        System.arraycopy(addr, 0, out, 4, addr.size)
        val portOff = 4 + addr.size
        out[portOff] = ((remotePort ushr 8) and 0xff).toByte()
        out[portOff + 1] = (remotePort and 0xff).toByte()
        System.arraycopy(payload, 0, out, headerLen, payload.size)
        return out
    }

    /**
     * Parse a SOCKS5 UDP reply. Returns null if truncated or unsupported.
     * Domain ATYP is supported for completeness; production path uses IP.
     */
    fun unwrap(packet: ByteArray, length: Int = packet.size): Datagram? {
        if (length < 4) return null
        val frag = packet[2].toInt() and 0xff
        if (frag != 0) return null // fragmented datagrams not supported
        val atyp = packet[3].toInt() and 0xff
        var offset = 4
        val addr: ByteArray =
            when (atyp) {
                ATYP_IPV4 -> {
                    if (length < offset + 4 + 2) return null
                    packet.copyOfRange(offset, offset + 4).also { offset += 4 }
                }
                ATYP_IPV6 -> {
                    if (length < offset + 16 + 2) return null
                    packet.copyOfRange(offset, offset + 16).also { offset += 16 }
                }
                ATYP_DOMAIN -> {
                    if (length < offset + 1) return null
                    val dlen = packet[offset].toInt() and 0xff
                    offset += 1
                    if (length < offset + dlen + 2) return null
                    // Domain form is rare on the reply path; resolve is not done here.
                    // Treat as unsupported for the NAT reverse path.
                    return null
                }
                else -> return null
            }
        if (length < offset + 2) return null
        val port = ((packet[offset].toInt() and 0xff) shl 8) or (packet[offset + 1].toInt() and 0xff)
        offset += 2
        val payload =
            if (offset >= length) {
                ByteArray(0)
            } else {
                packet.copyOfRange(offset, length)
            }
        return Datagram(
            remote = InetAddress.getByAddress(addr),
            remotePort = port,
            payload = payload,
            frag = frag,
        )
    }
}
