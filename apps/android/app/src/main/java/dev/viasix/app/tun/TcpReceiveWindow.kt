package dev.viasix.app.tun

/** RFC 9293 segment acceptability against ViaSix's advertised receive window. */
internal object TcpReceiveWindow {
    fun accepts(
        sequence: Long,
        payloadLength: Int,
        fin: Boolean,
        nextExpected: Long,
        receiveWindow: Int = Packet.TCP_WINDOW_SIZE,
    ): Boolean {
        require(payloadLength >= 0) { "payloadLength must not be negative" }
        require(receiveWindow in 0..65_535) { "receiveWindow must be 0..65535" }
        val segmentLength = payloadLength + if (fin) 1 else 0
        if (receiveWindow == 0) return segmentLength == 0 && sequence == nextExpected
        if (insideWindow(sequence, nextExpected, receiveWindow)) return true
        if (segmentLength == 0) return false
        val lastSequence = TcpSequence.advance(sequence, payloadLength = segmentLength - 1)
        return insideWindow(lastSequence, nextExpected, receiveWindow)
    }

    private fun insideWindow(
        sequence: Long,
        nextExpected: Long,
        receiveWindow: Int,
    ): Boolean = TcpSequence.forwardDistance(nextExpected, sequence) < receiveWindow.toLong()
}
