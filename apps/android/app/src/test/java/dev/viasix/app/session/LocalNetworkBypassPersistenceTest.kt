package dev.viasix.app.session

import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.app.state.SessionUiState
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalNetworkBypassPersistenceTest {
    @Test
    fun defaultsOffToPreserveFullTunnelRouting() {
        val state = SessionUiState.fromPrefs(SessionPrefs())

        assertFalse(state.bypassLocalNetwork)
        assertFalse(state.toPrefs().bypassLocalNetwork)
    }

    @Test
    fun enabledChoiceRoundTripsThroughUiState() {
        val state = SessionUiState.fromPrefs(SessionPrefs(bypassLocalNetwork = true))

        assertTrue(state.bypassLocalNetwork)
        assertTrue(state.toPrefs().bypassLocalNetwork)
    }
}
