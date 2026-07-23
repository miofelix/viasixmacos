package dev.viasix.app.session

import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.app.state.SessionUiState
import org.junit.Assert.assertEquals
import org.junit.Test

class AppRoutingPersistenceTest {
    @Test
    fun preferencesAndUiStateRoundTripAppRouting() {
        val sourcePrefs =
            SessionPrefs(
                appRoutingMode = AppRoutingMode.ONLY_SELECTED.wire,
                selectedAppPackages = listOf("com.example.chat", "com.example.browser"),
            )
        val state = SessionUiState.fromPrefs(sourcePrefs)

        assertEquals(AppRoutingMode.ONLY_SELECTED, state.appRouting.mode)
        assertEquals(
            listOf("com.example.browser", "com.example.chat"),
            state.appRouting.selectedPackages,
        )
        assertEquals(AppRoutingMode.ONLY_SELECTED.wire, state.toPrefs().appRoutingMode)
        assertEquals(state.appRouting.selectedPackages, state.toPrefs().selectedAppPackages)
    }
}
