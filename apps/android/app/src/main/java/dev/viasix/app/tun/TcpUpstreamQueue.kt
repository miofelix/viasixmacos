package dev.viasix.app.tun

class TcpUpstreamQueue(
    private val maxBytes: Int = 65_535,
    private val maxSegments: Int = 64,
) {
    private val monitor = Object()
    private val queue = ArrayDeque<ByteArray>()
    private var bufferedBytes = 0
    private var inFlightSegments = 0
    private var cancelled = false

    init {
        require(maxBytes > 0) { "maxBytes must be positive" }
        require(maxSegments > 0) { "maxSegments must be positive" }
    }

    val hasPending: Boolean
        get() =
            synchronized(monitor) {
                !cancelled && (queue.isNotEmpty() || inFlightSegments > 0)
            }

    fun offer(payload: ByteArray): Boolean =
        synchronized(monitor) {
            if (cancelled || payload.isEmpty()) return@synchronized !cancelled
            if (
                queue.size + inFlightSegments >= maxSegments ||
                    bufferedBytes + payload.size > maxBytes
            ) {
                return@synchronized false
            }
            queue.addLast(payload.copyOf())
            bufferedBytes += payload.size
            monitor.notifyAll()
            true
        }

    fun poll(timeoutMs: Long): ByteArray? =
        synchronized(monitor) {
            val deadline = System.nanoTime() + timeoutMs.coerceAtLeast(0L) * NANOS_PER_MILLISECOND
            while (!cancelled && queue.isEmpty()) {
                val remainingNanos = deadline - System.nanoTime()
                if (remainingNanos <= 0L) return@synchronized null
                try {
                    monitor.wait(
                        remainingNanos / NANOS_PER_MILLISECOND,
                        (remainingNanos % NANOS_PER_MILLISECOND).toInt(),
                    )
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return@synchronized null
                }
            }
            if (cancelled) return@synchronized null
            val payload = queue.removeFirst()
            inFlightSegments += 1
            payload
        }

    fun complete(payloadLength: Int) {
        synchronized(monitor) {
            if (cancelled || inFlightSegments <= 0) return
            bufferedBytes = (bufferedBytes - payloadLength.coerceAtLeast(0)).coerceAtLeast(0)
            inFlightSegments -= 1
            monitor.notifyAll()
        }
    }

    fun awaitEmpty(timeoutMs: Long): Boolean =
        synchronized(monitor) {
            val deadline = System.nanoTime() + timeoutMs.coerceAtLeast(0L) * NANOS_PER_MILLISECOND
            while (!cancelled && (queue.isNotEmpty() || inFlightSegments > 0)) {
                val remainingNanos = deadline - System.nanoTime()
                if (remainingNanos <= 0L) return@synchronized false
                try {
                    monitor.wait(
                        remainingNanos / NANOS_PER_MILLISECOND,
                        (remainingNanos % NANOS_PER_MILLISECOND).toInt(),
                    )
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return@synchronized false
                }
            }
            !cancelled && queue.isEmpty() && inFlightSegments == 0
        }

    fun cancel() {
        synchronized(monitor) {
            cancelled = true
            queue.clear()
            bufferedBytes = 0
            inFlightSegments = 0
            monitor.notifyAll()
        }
    }

    private companion object {
        const val NANOS_PER_MILLISECOND = 1_000_000L
    }
}
