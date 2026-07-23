package dev.viasix.app.session

import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.app.state.SessionUiState
import org.junit.Assert.assertEquals
import org.junit.Test

class Ipv6RoutingPersistenceTest {
    @Test
    fun modeRoundTripsThroughPreferencesAndUiState() {
        for (mode in Ipv6RoutingMode.entries) {
            val state =
                SessionUiState.fromPrefs(
                    SessionPrefs(ipv6RoutingMode = mode.wire),
                )

            assertEquals(mode, state.ipv6RoutingMode)
            assertEquals(mode.wire, state.toPrefs().ipv6RoutingMode)
        }
    }
}
