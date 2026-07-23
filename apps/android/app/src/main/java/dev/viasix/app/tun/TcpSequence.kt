package dev.viasix.app.tun

object TcpSequence {
    private const val MASK = 0xffff_ffffL
    private const val HALF_RANGE = 0x8000_0000L

    fun advance(
        sequence: Long,
        payloadLength: Int = 0,
        syn: Boolean = false,
        fin: Boolean = false,
    ): Long =
        (sequence + payloadLength + (if (syn) 1 else 0) + (if (fin) 1 else 0)) and MASK

    fun isAfter(
        candidate: Long,
        reference: Long,
    ): Boolean {
        val distance = (candidate - reference) and MASK
        return distance != 0L && distance < HALF_RANGE
    }

    fun forwardDistance(
        from: Long,
        to: Long,
    ): Long = (to - from) and MASK

    /** Null means the segment starts ahead of the next expected byte (out of order). */
    fun consumedPayloadPrefix(
        segmentStart: Long,
        payloadLength: Int,
        nextExpected: Long,
    ): Int? {
        require(payloadLength >= 0) { "negative payload length" }
        if (isAfter(segmentStart, nextExpected)) return null
        val consumed = (nextExpected - segmentStart) and MASK
        return consumed.coerceAtMost(payloadLength.toLong()).toInt()
    }
}
