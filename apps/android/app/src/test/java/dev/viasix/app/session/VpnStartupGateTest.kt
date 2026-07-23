package dev.viasix.app.session

import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnStartupGateTest {
    @Test
    fun activeStartupPassesCheckpoint() {
        VpnStartupGate.requireActive(shuttingDown = false, stage = "VPN establish")
    }

    @Test
    fun shutdownCancelsStartupWithCheckpointContext() {
        val error =
            assertThrows(VpnStartupCancelledException::class.java) {
                VpnStartupGate.requireActive(
                    shuttingDown = true,
                    stage = "after mihomo launch",
                )
            }

        assertTrue(error.message.orEmpty().contains("after mihomo launch"))
    }
}
