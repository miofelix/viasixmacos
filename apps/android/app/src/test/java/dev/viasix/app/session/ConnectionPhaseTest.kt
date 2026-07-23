package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Drives real [ConnectionPhase] reconcile used by MainActivity poll loop. */
class ConnectionPhaseTest {
    @Test
    fun reconcile_runtimeRunningBecomesRunning() {
        assertEquals(
            ConnectionPhase.RUNNING,
            ConnectionPhase.reconcile(ConnectionPhase.STARTING, runtimeRunning = true),
        )
        assertEquals(
            ConnectionPhase.RUNNING,
            ConnectionPhase.reconcile(ConnectionPhase.STOPPED, runtimeRunning = true),
        )
    }

    @Test
    fun reconcile_stoppingWithoutRuntimeBecomesStopped() {
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.reconcile(ConnectionPhase.STOPPING, runtimeRunning = false),
        )
    }

    @Test
    fun reconcile_keepsStartingUntilTimeoutHelper() {
        assertEquals(
            ConnectionPhase.STARTING,
            ConnectionPhase.reconcile(ConnectionPhase.STARTING, runtimeRunning = false),
        )
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.afterStartTimeout(ConnectionPhase.STARTING, runtimeRunning = false),
        )
    }

    @Test
    fun reconcile_unexpectedDropFromRunning() {
        assertEquals(
            ConnectionPhase.STOPPED,
            ConnectionPhase.reconcile(ConnectionPhase.RUNNING, runtimeRunning = false),
        )
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
        assertTrue(ConnectionPhase.RUNNING.isActiveOrTransitioning)
        assertFalse(ConnectionPhase.STOPPED.isActiveOrTransitioning)
    }
}
