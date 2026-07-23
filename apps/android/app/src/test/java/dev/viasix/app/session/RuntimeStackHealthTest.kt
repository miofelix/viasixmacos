package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RuntimeStackHealthTest {
    @Test
    fun detectsRequiredRuntimeComponentExit() {
        assertEquals(
            RuntimeStackFailure.MIHOMO_EXITED,
            RuntimeStackHealth.failure(
                mihomoRunning = false,
                fullTunnel = false,
                tunnelRunning = false,
            ),
        )
        assertEquals(
            RuntimeStackFailure.TUNNEL_EXITED,
            RuntimeStackHealth.failure(
                mihomoRunning = true,
                fullTunnel = true,
                tunnelRunning = false,
            ),
        )
    }

    @Test
    fun proxyModeDoesNotRequireTunEngine() {
        assertNull(
            RuntimeStackHealth.failure(
                mihomoRunning = true,
                fullTunnel = false,
                tunnelRunning = false,
            ),
        )
    }
}
