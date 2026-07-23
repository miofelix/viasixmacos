package dev.viasix.app.tun

/** RFC 9293 reset fields for a segment received while no TCP control block exists. */
internal object TcpClosedStateReset {
    data class Reply(
        val sequence: Long,
        val acknowledgement: Long,
        val flags: Int,
    )

    fun forSegment(segment: Packet.Tcp): Reply? {
        if (segment.flags and Packet.RST != 0) return null
        if (segment.flags and Packet.ACK != 0) {
            return Reply(
                sequence = segment.ack,
                acknowledgement = 0L,
                flags = Packet.RST,
            )
        }
        return Reply(
            sequence = 0L,
            acknowledgement =
                TcpSequence.advance(
                    sequence = segment.seq,
                    payloadLength = segment.payloadLength,
                    syn = segment.flags and Packet.SYN != 0,
                    fin = segment.flags and Packet.FIN != 0,
                ),
            flags = Packet.RST or Packet.ACK,
        )
    }
}
