package dev.viasix.app.tun

/** RFC 5961 validation for an RST received in a synchronized TCP state. */
internal object TcpResetPolicy {
    enum class Action {
        CLOSE,
        CHALLENGE_ACK,
        DROP,
    }

    fun classify(
        sequence: Long,
        nextExpected: Long,
        receiveWindow: Int = Packet.TCP_WINDOW_SIZE,
    ): Action {
        require(receiveWindow in 0..65_535) { "receiveWindow must be 0..65535" }
        if (sequence == nextExpected) return Action.CLOSE
        if (receiveWindow == 0) return Action.DROP
        val distance = TcpSequence.forwardDistance(nextExpected, sequence)
        return if (distance in 1 until receiveWindow.toLong()) {
            Action.CHALLENGE_ACK
        } else {
            Action.DROP
        }
    }
}
