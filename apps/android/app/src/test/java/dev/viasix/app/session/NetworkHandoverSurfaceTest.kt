package dev.viasix.app.session

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class NetworkHandoverSurfaceTest {
    @Test
    fun defaultNetworkFlowsThroughServiceRuntimeAndUi() {
        val manifest = resolve("src/main/AndroidManifest.xml", "app/src/main/AndroidManifest.xml").readText()
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()
        val runtimeStore =
            resolve(
                "src/main/java/dev/viasix/app/session/SessionRuntimeStore.kt",
                "app/src/main/java/dev/viasix/app/session/SessionRuntimeStore.kt",
            ).readText()
        val overview =
            resolve(
                "src/main/java/dev/viasix/app/ui/screens/OverviewScreen.kt",
                "app/src/main/java/dev/viasix/app/ui/screens/OverviewScreen.kt",
            ).readText()
        val settings =
            resolve(
                "src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt",
                "app/src/main/java/dev/viasix/app/ui/screens/SettingsScreen.kt",
            ).readText()

        assertTrue(manifest.contains("android.permission.ACCESS_NETWORK_STATE"))
        assertTrue(service.contains("registerDefaultNetworkCallback(underlyingNetworkCallback)"))
        assertTrue(service.contains("NetworkCapabilities.NET_CAPABILITY_NOT_VPN"))
        assertTrue(service.contains("setUnderlyingNetworks(arrayOf(network))"))
        assertTrue(service.contains("setUnderlyingNetworks(null)"))
        assertTrue(service.contains("unregisterNetworkCallback(underlyingNetworkCallback)"))
        assertTrue(runtimeStore.contains("ViaSixVpnService.KEY_UNDERLYING_NETWORK"))
        assertTrue(overview.contains("\"底层网络\""))
        assertTrue(overview.contains("state.runtime.underlyingNetwork"))
        assertTrue(settings.contains("\"底层网络\""))
        assertTrue(settings.contains("state.runtime.underlyingNetwork"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
