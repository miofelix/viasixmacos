package dev.viasix.app.session

import dev.viasix.app.state.SessionUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfileDraftGateTest {
    @Test
    fun managedDefaultProfileIsReady() {
        assertEquals(
            ProfileDraftGate.Result.Ok,
            ProfileDraftGate.evaluate(SessionUiState.defaultProfile),
        )
    }

    @Test
    fun malformedYamlIsBlocked() {
        val result = ProfileDraftGate.evaluate("proxies: [")
        assertTrue(result is ProfileDraftGate.Result.Blocked)
        assertTrue((result as ProfileDraftGate.Result.Blocked).message.contains("YAML"))
    }

    @Test
    fun unmanagedProfileIsBlocked() {
        val result =
            ProfileDraftGate.evaluate(
                """
                proxies:
                  - name: edge
                    type: vless
                    server: example.com
                    port: 443
                """.trimIndent(),
            )
        assertEquals(
            "缺少 x-viasix 管理段",
            (result as ProfileDraftGate.Result.Blocked).message,
        )
    }

    @Test
    fun wrongPrimaryMarkerIsBlocked() {
        val result =
            ProfileDraftGate.evaluate(
                SessionUiState.defaultProfile.replace("selected-ip", "edge"),
            )
        assertEquals(
            "x-viasix.primary-server 必须为 selected-ip",
            (result as ProfileDraftGate.Result.Blocked).message,
        )
    }
}
