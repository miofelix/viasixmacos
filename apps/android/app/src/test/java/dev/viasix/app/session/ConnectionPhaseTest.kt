package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Drives real [ConnectionPhase] reconcile used by MainActivity poll loop. */
class ConnectionPhaseTest {
    @Test
    fun restoreUsesRuntimeAndPendingConsentState() {
        assertEquals(
            ConnectionPhase.RUNNING,
            ConnectionPhase.restore(runtimePhase = ConnectionPhase.RUNNING),
        )
        assertEquals(
            ConnectionPhase.STARTING,
            ConnectionPhase.restore(
                runtimePhase = ConnectionPhase.STOPPED,
                hasPendingStart = true,
            ),
        )
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.restore(runtimePhase = ConnectionPhase.STOPPED),
        )
    }

    @Test
    fun reconcile_runtimeRunningBecomesRunning() {
        assertEquals(
            ConnectionPhase.RUNNING,
            ConnectionPhase.reconcile(ConnectionPhase.STARTING, ConnectionPhase.RUNNING),
        )
        assertEquals(
            ConnectionPhase.RUNNING,
            ConnectionPhase.reconcile(ConnectionPhase.STOPPED, ConnectionPhase.RUNNING),
        )
    }

    @Test
    fun reconcile_stoppingWithoutRuntimeBecomesStopped() {
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.reconcile(ConnectionPhase.STOPPING, ConnectionPhase.STOPPED),
        )
    }

    @Test
    fun reconcile_keepsStartingUntilTimeoutHelper() {
        assertEquals(
            ConnectionPhase.STARTING,
            ConnectionPhase.reconcile(ConnectionPhase.STARTING, ConnectionPhase.STOPPED),
        )
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.afterStartTimeout(ConnectionPhase.STARTING, ConnectionPhase.STOPPED),
        )
    }

    @Test
    fun afterStartTimeout_clearsStuckRuntimeStarting() {
        // Service published STARTING but never reached RUNNING (hung worker).
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.afterStartTimeout(
                ConnectionPhase.STARTING,
                ConnectionPhase.STARTING,
            ),
        )
        // Late success still wins.
        assertEquals(
            ConnectionPhase.RUNNING,
            ConnectionPhase.afterStartTimeout(
                ConnectionPhase.STARTING,
                ConnectionPhase.RUNNING,
            ),
        )
    }

    @Test
    fun shouldApplyStartTimeout_coversStoppedAndStuckStarting() {
        val t0 = 1_000_000L
        val timeout = 25_000L
        assertTrue(
            ConnectionPhase.shouldApplyStartTimeout(
                uiPhase = ConnectionPhase.STARTING,
                runtimePhase = ConnectionPhase.STOPPED,
                runtimeRunning = false,
                startingSinceMillis = t0,
                nowMillis = t0 + timeout + 1,
                timeoutMs = timeout,
            ),
        )
        assertTrue(
            ConnectionPhase.shouldApplyStartTimeout(
                uiPhase = ConnectionPhase.STARTING,
                runtimePhase = ConnectionPhase.STARTING,
                runtimeRunning = false,
                startingSinceMillis = t0,
                nowMillis = t0 + timeout + 1,
                timeoutMs = timeout,
            ),
        )
        assertFalse(
            ConnectionPhase.shouldApplyStartTimeout(
                uiPhase = ConnectionPhase.STARTING,
                runtimePhase = ConnectionPhase.STARTING,
                runtimeRunning = false,
                startingSinceMillis = t0,
                nowMillis = t0 + timeout - 1,
                timeoutMs = timeout,
            ),
        )
        assertFalse(
            ConnectionPhase.shouldApplyStartTimeout(
                uiPhase = ConnectionPhase.STARTING,
                runtimePhase = ConnectionPhase.RUNNING,
                runtimeRunning = true,
                startingSinceMillis = t0,
                nowMillis = t0 + timeout + 1,
                timeoutMs = timeout,
            ),
        )
    }

    @Test
    fun reconcile_unexpectedDropFromRunning() {
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.reconcile(ConnectionPhase.RUNNING, ConnectionPhase.STOPPED),
        )
    }

    @Test
    fun runtimeTransitionsRemainAuthoritativeAcrossUiRecreation() {
        assertEquals(
            ConnectionPhase.STARTING,
            ConnectionPhase.restore(runtimePhase = ConnectionPhase.STARTING),
        )
        assertEquals(
            ConnectionPhase.STOPPING,
            ConnectionPhase.reconcile(ConnectionPhase.RUNNING, ConnectionPhase.STOPPING),
        )
        assertEquals(ConnectionPhase.STARTING, ConnectionPhase.parse("starting"))
        assertEquals("stopping", ConnectionPhase.STOPPING.wire)
    }

    @Test
    fun labelsAndBusyFlags() {
        assertEquals("连接", ConnectionPhase.STOPPED.actionLabel())
        assertEquals("连接中…", ConnectionPhase.STARTING.actionLabel())
        assertEquals("断开", ConnectionPhase.RUNNING.actionLabel())
        assertEquals("断开中…", ConnectionPhase.STOPPING.actionLabel())
        assertTrue(ConnectionPhase.STARTING.isBusy)
        assertTrue(ConnectionPhase.STOPPING.isBusy)
        assertFalse(ConnectionPhase.RUNNING.isBusy)
        assertTrue(ConnectionPhase.STARTING.isActiveOrTransitioning)
        assertTrue(ConnectionPhase.RUNNING.isActiveOrTransitioning)
        assertTrue(ConnectionPhase.STOPPING.isActiveOrTransitioning)
        assertFalse(ConnectionPhase.STOPPED.isActiveOrTransitioning)
    }
}
