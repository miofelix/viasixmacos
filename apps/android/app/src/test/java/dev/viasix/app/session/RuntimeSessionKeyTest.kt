package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuntimeSessionKeyTest {
    @Test
    fun runningRuntimeWithPublishedControllerHasSessionKey() {
        val key = runtime().sessionKey()

        assertEquals(
            RuntimeSessionKey(
                processToken = "process-a",
                secret = "secret-a",
                startedAtMillis = 42L,
                controllerPort = 9191,
            ),
            key,
        )
    }

    @Test
    fun transitionalAndStoppedRuntimeHaveNoSessionKey() {
        listOf(
            ConnectionPhase.STOPPED,
            ConnectionPhase.STARTING,
            ConnectionPhase.STOPPING,
        ).forEach { phase ->
            assertNull(runtime().copy(running = false, phase = phase).sessionKey())
        }
    }

    @Test
    fun incompleteControllerIdentityHasNoSessionKey() {
        assertNull(runtime().copy(secret = "").sessionKey())
        assertNull(runtime().copy(processToken = "").sessionKey())
    }

    @Test
    fun restartedOrRepublishedControllerChangesSessionKey() {
        val original = runtime().sessionKey()

        assertNotEquals(original, runtime().copy(secret = "secret-b").sessionKey())
        assertNotEquals(original, runtime().copy(startedAtMillis = 43L).sessionKey())
        assertNotEquals(original, runtime().copy(controllerPort = 9292).sessionKey())
    }

    private fun runtime(): SessionRuntimeStatus =
        SessionRuntimeStatus(
            running = true,
            phase = ConnectionPhase.RUNNING,
            controllerPort = 9191,
            secret = "secret-a",
            startedAtMillis = 42L,
            processToken = "process-a",
        )
}
