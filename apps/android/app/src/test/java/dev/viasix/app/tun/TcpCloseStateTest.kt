package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpCloseStateTest {
    @Test
    fun fullCloseRequiresBothClientFinAndServerFinAcknowledgement() {
        val state = TcpCloseState()

        assertTrue(state.markClientFin())
        assertFalse(state.isFullyClosed)
        assertTrue(state.markServerFin(sequenceEnd = 500L, nowMs = 1_000L))
        assertFalse(state.acknowledgeServerFin(acknowledgement = 499L))
        assertFalse(state.isFullyClosed)
        assertTrue(state.acknowledgeServerFin(acknowledgement = 500L))
        assertTrue(state.isFullyClosed)
    }

    @Test
    fun duplicateFinSignalsDoNotResetStateOrLingerDeadline() {
        val state = TcpCloseState()

        assertTrue(state.markClientFin())
        assertFalse(state.markClientFin())
        assertTrue(state.markServerFin(sequenceEnd = 0L, nowMs = 10L))
        assertFalse(state.markServerFin(sequenceEnd = 1L, nowMs = 1_000L))
        assertFalse(state.isExpired(nowMs = 1_009L, timeoutMs = 1_000L))
        assertTrue(state.isExpired(nowMs = 1_010L, timeoutMs = 1_000L))
    }
}
