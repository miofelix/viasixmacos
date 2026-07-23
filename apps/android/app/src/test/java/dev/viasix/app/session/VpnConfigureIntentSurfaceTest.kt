package dev.viasix.app.session

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class VpnConfigureIntentSurfaceTest {
    @Test
    fun systemVpnConfigureActionReturnsToSettingsOnColdOrWarmActivity() {
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()
        val activity =
            resolve(
                "src/main/java/dev/viasix/app/MainActivity.kt",
                "app/src/main/java/dev/viasix/app/MainActivity.kt",
            ).readText()

        assertTrue(service.contains(".setConfigureIntent(buildConfigureIntent())"))
        assertTrue(service.contains("MainActivity.EXTRA_OPEN_SECTION"))
        assertTrue(service.contains("AppSection.SETTINGS.wire"))
        assertTrue(service.contains("Intent.FLAG_ACTIVITY_CLEAR_TOP"))
        assertTrue(service.contains("Intent.FLAG_ACTIVITY_SINGLE_TOP"))
        assertTrue(service.contains("PendingIntent.FLAG_IMMUTABLE"))
        assertTrue(activity.contains("getStringExtra(EXTRA_OPEN_SECTION)"))
        assertTrue(activity.contains("removeExtra(EXTRA_OPEN_SECTION)"))
        assertTrue(activity.contains("selectSection(AppSection.parse(it))"))
        assertTrue(activity.contains("override fun onNewIntent"))
        assertTrue(activity.contains("intent?.let(::handleLaunchIntent)"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
