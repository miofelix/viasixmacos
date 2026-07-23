package dev.viasix.app.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class AppRoutingSurfaceTest {
    @Test
    fun manifestDiscoverySettingsAndVpnBuilderExposePerAppRouting() {
        val manifest = resolve("src/main/AndroidManifest.xml", "app/src/main/AndroidManifest.xml").readText()
        val repository =
            resolve(
                "src/main/java/dev/viasix/app/session/InstalledAppsRepository.kt",
                "app/src/main/java/dev/viasix/app/session/InstalledAppsRepository.kt",
            ).readText()
        val model =
            resolve(
                "src/main/java/dev/viasix/app/session/AppRouting.kt",
                "app/src/main/java/dev/viasix/app/session/AppRouting.kt",
            ).readText()
        val preferences =
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

        assertTrue(manifest.contains("<queries>"))
        assertTrue(manifest.contains("android.intent.category.LAUNCHER"))
        assertFalse(manifest.contains("QUERY_ALL_PACKAGES"))
        assertTrue(repository.contains("queryIntentActivities"))
        assertTrue(model.contains("仅代理所选应用"))
        assertTrue(preferences.contains("\"appRoutingMode\""))
        assertTrue(preferences.contains("\"selectedAppPackages\""))
        assertTrue(commands.contains("EXTRA_APP_ROUTING_MODE"))
        assertTrue(commands.contains("EXTRA_SELECTED_APP_PACKAGES"))
        assertTrue(service.contains("builder.addAllowedApplication"))
        assertTrue(service.contains("builder.addDisallowedApplication"))
        assertTrue(settings.contains("分应用路由"))
        assertTrue(settings.contains("AppRoutingMode.entries"))
        assertTrue(settings.contains("搜索名称或包名"))
        assertTrue(settings.contains("高级：手动包名"))
        assertTrue(settings.contains("AppRoutingPolicy.isValidPackageName"))
        assertTrue(settings.contains("运行中不可修改应用路由"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
