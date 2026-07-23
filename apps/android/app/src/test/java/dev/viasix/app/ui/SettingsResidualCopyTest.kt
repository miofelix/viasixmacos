package dev.viasix.app.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Guards against stale Settings copy that under-claims the shipped full-tunnel path.
 * Reads the real [SettingsScreen] source from the module tree.
 */
class SettingsResidualCopyTest {
    @Test
    fun settingsDoesNotClaimFullTunnelStillOnRoadmap() {
        val source = resolveSettingsScreenSource()
        val text = source.readText()
        assertFalse(
            "Settings must not say production tun2socks / full UDP·IPv6 is still on the roadmap",
            text.contains("生产级 tun2socks") || text.contains("完整 UDP·IPv6 转发仍在路线图"),
        )
        assertTrue(
            "Settings should describe shipped TCP/UDP tunnel or optional hev residual",
            text.contains("TCP/UDP") && text.contains("native hev"),
        )
    }

    private fun resolveSettingsScreenSource(): File {
        val candidates =
            listOf(
                // gradle :app working dir
                File("src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt"),
                File("app/src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt"),
                // monorepo root
                File("apps/android/app/src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt"),
            )
        return candidates.firstOrNull { it.isFile }
            ?: error("SettingsScreen.kt not found from cwd=${File(".").absolutePath}")
    }
}
