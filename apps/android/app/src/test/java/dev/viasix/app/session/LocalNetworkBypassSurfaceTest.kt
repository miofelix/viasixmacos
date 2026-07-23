package dev.viasix.app.session

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class LocalNetworkBypassSurfaceTest {
    @Test
    fun nativeRouteExclusionsFlowThroughPrefsCommandsRestoreBuilderAndSettings() {
        val prefs =
            resolve(
                "src/main/java/dev/viasix/app/prefs/SessionPrefs.kt",
                "app/src/main/java/dev/viasix/app/prefs/SessionPrefs.kt",
            ).readText()
        val commands =
            resolve(
                "src/main/java/dev/viasix/app/session/VpnSessionCommands.kt",
                "app/src/main/java/dev/viasix/app/session/VpnSessionCommands.kt",
            ).readText()
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()
        val settings =
            resolve(
                "src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt",
                "app/src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt",
            ).readText()

        assertTrue(prefs.contains(".put(\"bypassLocalNetwork\", bypassLocalNetwork)"))
        assertTrue(prefs.contains("o.optBoolean(\"bypassLocalNetwork\", false)"))
        assertTrue(commands.contains("EXTRA_BYPASS_LOCAL_NETWORK"))
        assertTrue(commands.contains("prefs.bypassLocalNetwork"))
        assertTrue(service.contains("restoredPrefs?.bypassLocalNetwork"))
        assertTrue(service.contains("Build.VERSION_CODES.TIRAMISU"))
        assertTrue(service.contains("builder.excludeRoute(IpPrefix(address, prefixLength))"))
        assertTrue(service.contains("LocalNetworkBypassPolicy.IPV4_PREFIXES"))
        assertTrue(service.contains("LocalNetworkBypassPolicy.IPV6_PREFIXES"))
        assertTrue(service.contains("preserveDnsVpnRoute"))
        assertTrue(service.contains("builder.addRoute(dnsAddress"))
        assertTrue(settings.contains("绕过局域网"))
        assertTrue(settings.contains("系统锁定 VPN 仍可能阻止隧道外流量"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
