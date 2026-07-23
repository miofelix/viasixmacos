package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpChallengeAckLimiterTest {
    @Test
    fun firstChallengeIsImmediateAndRepeatsAreRateLimited() {
        val limiter = TcpChallengeAckLimiter(minimumIntervalMs = 1_000L)

        assertTrue(limiter.tryAcquire(nowMs = 5_000L))
        assertFalse(limiter.tryAcquire(nowMs = 5_999L))
        assertTrue(limiter.tryAcquire(nowMs = 6_000L))
        assertFalse(limiter.tryAcquire(nowMs = 6_500L))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsNonPositiveInterval() {
        TcpChallengeAckLimiter(minimumIntervalMs = 0L)
    }
}
