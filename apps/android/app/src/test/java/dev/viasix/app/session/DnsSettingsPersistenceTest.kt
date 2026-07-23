package dev.viasix.app.session

import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.app.state.SessionUiState
import org.junit.Assert.assertEquals
import org.junit.Test

class DnsSettingsPersistenceTest {
    @Test
    fun preferencesAndUiStateRoundTripDnsModeAndServer() {
        val state =
            SessionUiState.fromPrefs(
                SessionPrefs(
                    dnsRoutingMode = DnsRoutingMode.DIRECT.wire,
                    dnsServer = "2606:4700:4700::1111",
                ),
            )

        assertEquals(DnsRoutingMode.DIRECT, state.dnsSettings.mode)
        assertEquals("2606:4700:4700::1111", state.dnsSettings.server)
        assertEquals(DnsRoutingMode.DIRECT.wire, state.toPrefs().dnsRoutingMode)
        assertEquals("2606:4700:4700::1111", state.toPrefs().dnsServer)
    }

    @Test
    fun invalidDraftRemainsVisibleUntilUserFixesIt() {
        val state = SessionUiState.fromPrefs(SessionPrefs(dnsServer = "dns.example.com"))

        assertEquals("dns.example.com", state.dnsSettings.server)
        assertEquals("dns.example.com", state.toPrefs().dnsServer)
    }
}
