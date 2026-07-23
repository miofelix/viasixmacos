package dev.viasix.app.tun

class TcpSendWindow {
    private val monitor = Object()
    private var initialized = false
    private var acknowledgedSequence = 0L
    private var sentSequence = 0L
    private var advertisedBytes = 0
    private var cancelled = false

    fun update(
        acknowledgement: Long,
        advertisedWindow: Int,
        nextSequence: Long,
    ): Boolean =
        synchronized(monitor) {
            if (cancelled) return@synchronized false
            if (advertisedWindow !in 0..65_535) return@synchronized false
            if (!initialized) {
                if (acknowledgement != nextSequence) return@synchronized false
                acknowledgedSequence = acknowledgement
                sentSequence = nextSequence
                advertisedBytes = advertisedWindow
                initialized = true
                monitor.notifyAll()
                return@synchronized true
            }
            if (TcpSequence.isAfter(acknowledgement, sentSequence)) return@synchronized false
            if (
                acknowledgement != acknowledgedSequence &&
                    !TcpSequence.isAfter(acknowledgement, acknowledgedSequence)
            ) {
                return@synchronized false
            }
            acknowledgedSequence = acknowledgement
            advertisedBytes = advertisedWindow
            monitor.notifyAll()
            true
        }

    fun recordSent(
        sequence: Long,
        sequenceLength: Int,
    ): Boolean =
        synchronized(monitor) {
            if (cancelled || !initialized || sequenceLength <= 0) return@synchronized false
            if (sequence != sentSequence) return@synchronized false
            sentSequence = TcpSequence.advance(sentSequence, payloadLength = sequenceLength)
            true
        }

    fun awaitAllowance(
        maxBytes: Int,
        timeoutMs: Long,
    ): Int =
        synchronized(monitor) {
            require(maxBytes > 0) { "maxBytes must be positive" }
            val deadline = System.currentTimeMillis() + timeoutMs.coerceAtLeast(0L)
            while (!cancelled) {
                val available = availableBytes()
                if (available > 0) return@synchronized minOf(available, maxBytes)
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0L) return@synchronized 0
                try {
                    monitor.wait(remaining)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return@synchronized 0
                }
            }
            0
        }

    fun cancel() {
        synchronized(monitor) {
            cancelled = true
            monitor.notifyAll()
        }
    }

    private fun availableBytes(): Int {
        if (!initialized) return 0
        val inFlight = TcpSequence.forwardDistance(acknowledgedSequence, sentSequence)
        if (inFlight >= advertisedBytes.toLong()) return 0
        return (advertisedBytes - inFlight).toInt()
    }
}
