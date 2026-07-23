package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LatestRequestGateTest {
    @Test
    fun activeWorkerReceivesOnlyNewestPendingRequest() {
        val gate = LatestRequestGate<String>()

        assertTrue(gate.submit("first"))
        assertEquals("first", gate.takeNext())
        assertFalse(gate.submit("second"))
        assertFalse(gate.submit("latest"))

        assertEquals("latest", gate.takeNext())
        assertNull(gate.takeNext())
    }

    @Test
    fun idleGateLaunchesNewWorkerAfterPreviousWorkerRetires() {
        val gate = LatestRequestGate<String>()

        assertTrue(gate.submit("first"))
        assertEquals("first", gate.takeNext())
        assertNull(gate.takeNext())

        assertTrue(gate.submit("second"))
        assertEquals("second", gate.takeNext())
    }

    @Test
    fun cancellationDropsPendingRequestWithoutRevivingWorker() {
        val gate = LatestRequestGate<String>()

        assertTrue(gate.submit("active"))
        assertEquals("active", gate.takeNext())
        assertFalse(gate.submit("pending"))
        gate.cancelPending()

        assertNull(gate.takeNext())
    }
}
