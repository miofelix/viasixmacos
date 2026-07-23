package dev.viasix.app.session

import dev.viasix.app.mihomo.TrafficSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionRuntimeStatusTest {
    @Test
    fun persistedRuntimeMapsToImmediateUiSnapshot() {
        val traffic =
            TrafficSnapshot(
                live = true,
                upBps = 1_024L,
                downBps = 2_048L,
                connectionCount = 3,
            )
        val snapshot =
            SessionRuntimeStatus(
                running = true,
                health = "ok",
                controllerPort = 9191,
                mixedPort = 11888,
                secret = "secret",
                mihomoVersion = "v1.2.3",
                startedAtMillis = 42L,
                underlyingNetwork = "Wi-Fi · 已联网",
            ).toUiSnapshot(traffic)

        assertTrue(snapshot.running)
        assertEquals("ok", snapshot.health)
        assertEquals(9191, snapshot.controllerPort)
        assertEquals(11888, snapshot.mixedPort)
        assertEquals("v1.2.3", snapshot.mihomoVersion)
        assertEquals(42L, snapshot.startedAtMillis)
        assertEquals(traffic, snapshot.traffic)
        assertTrue(snapshot.secretPresent)
        assertEquals("Wi-Fi · 已联网", snapshot.underlyingNetwork)
    }

    @Test
    fun staleRunningStateFromAnotherProcessIsRejected() {
        val stale =
            SessionRuntimeStatus(
                running = true,
                health = "ok",
                secret = "secret",
                mihomoVersion = "v1.2.3",
                startedAtMillis = 42L,
                eventsJson = "[event]",
                processToken = "old-process",
            ).forProcess(currentProcessToken = "current-process")

        assertFalse(stale.running)
        assertEquals(ConnectionPhase.STOPPED, stale.phase)
        assertEquals("stopped", stale.health)
        assertEquals("", stale.secret)
        assertEquals(null, stale.mihomoVersion)
        assertEquals(null, stale.startedAtMillis)
        assertEquals("[event]", stale.eventsJson)
        assertEquals("", stale.processToken)
    }

    @Test
    fun runningStateOwnedByCurrentProcessIsPreserved() {
        val current =
            SessionRuntimeStatus(
                running = true,
                secret = "secret",
                processToken = "current-process",
            )

        assertEquals(current, current.forProcess(currentProcessToken = "current-process"))
    }

    @Test
    fun staleTransitionFromAnotherProcessIsRejected() {
        val stale =
            SessionRuntimeStatus(
                phase = ConnectionPhase.STARTING,
                health = "starting",
                processToken = "old-process",
            ).forProcess(currentProcessToken = "current-process")

        assertEquals(ConnectionPhase.STOPPED, stale.phase)
        assertFalse(stale.running)
        assertEquals("stopped", stale.health)
    }
}
