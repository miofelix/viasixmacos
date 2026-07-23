package dev.viasix.app.tun

import java.util.concurrent.atomic.AtomicLong

/** Per-session RFC 5961 challenge ACK rate limit. */
internal class TcpChallengeAckLimiter(
    private val minimumIntervalMs: Long = 1_000L,
) {
    private val lastSentAtMs = AtomicLong(NEVER_SENT)

    init {
        require(minimumIntervalMs > 0L) { "minimumIntervalMs must be positive" }
    }

    fun tryAcquire(nowMs: Long): Boolean {
        while (true) {
            val previous = lastSentAtMs.get()
            if (previous != NEVER_SENT && nowMs - previous < minimumIntervalMs) return false
            if (lastSentAtMs.compareAndSet(previous, nowMs)) return true
        }
    }

    private companion object {
        const val NEVER_SENT = Long.MIN_VALUE
    }
}
