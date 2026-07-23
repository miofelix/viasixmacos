package dev.viasix.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class Ipv6RoutingSurfaceTest {
    @Test
    fun modesFlowThroughPrefsCommandsRestoreBuilderAndSettings() {
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

        assertTrue(prefs.contains(".put(\"ipv6RoutingMode\", ipv6RoutingMode)"))
        assertTrue(prefs.contains("o.optString(\"ipv6RoutingMode\", \"tunnel\")"))
        assertTrue(commands.contains("EXTRA_IPV6_ROUTING_MODE"))
        assertTrue(commands.contains("prefs.ipv6RoutingMode"))
        assertTrue(service.contains("restoredPrefs?.ipv6RoutingMode"))
        assertTrue(service.contains("Ipv6RoutingMode.BLOCK -> Unit"))
        assertTrue(service.contains("builder.allowFamily(OsConstants.AF_INET6)"))
        assertTrue(service.contains("HTTP proxy-only publishes metadata without a default route"))
        assertTrue(service.contains("IPv6 VPN route is required but could not be applied"))
        assertFalse(service.contains("IPv6 route not applied"))
        assertFalse(service.contains("IPv6 默认路由未应用"))
        assertTrue(settings.contains("IPv6 应用流量"))
        assertTrue(settings.contains("Ipv6RoutingMode.BYPASS"))
        assertTrue(settings.contains("colors.warning"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
