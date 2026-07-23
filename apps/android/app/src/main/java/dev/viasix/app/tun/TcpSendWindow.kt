package dev.viasix.app.tun

class TcpSendWindow(
    private val maxInFlightBytes: Int = TcpRetransmissionQueue.DEFAULT_MAX_RETAINED_BYTES,
) {
    private val monitor = Object()
    private var initialized = false
    private var acknowledgedSequence = 0L
    private var sentSequence = 0L
    private var advertisedBytes = 0
    private var cancelled = false

    init {
        require(maxInFlightBytes > 0) { "maxInFlightBytes must be positive" }
    }

    fun update(
        acknowledgement: Long,
        advertisedWindow: Int,
        nextSequence: Long,
    ): Boolean =
        synchronized(monitor) {
            if (cancelled) return@synchronized false
            if (advertisedWindow < 0) return@synchronized false
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
            val deadline = System.nanoTime() + timeoutMs.coerceAtLeast(0L) * NANOS_PER_MILLISECOND
            while (!cancelled) {
                val available = availableBytes()
                if (available > 0) return@synchronized minOf(available, maxBytes)
                val remainingNanos = deadline - System.nanoTime()
                if (remainingNanos <= 0L) return@synchronized 0
                try {
                    monitor.wait(
                        remainingNanos / NANOS_PER_MILLISECOND,
                        (remainingNanos % NANOS_PER_MILLISECOND).toInt(),
                    )
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return@synchronized 0
                }
            }
            0
        }

    fun acknowledgedSequence(): Long? =
        synchronized(monitor) {
            if (!initialized || cancelled) null else acknowledgedSequence
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
        val effectiveWindow = minOf(advertisedBytes, maxInFlightBytes).toLong()
        if (inFlight >= effectiveWindow) return 0
        return (effectiveWindow - inFlight).toInt()
    }

    private companion object {
        const val NANOS_PER_MILLISECOND = 1_000_000L
    }
}
