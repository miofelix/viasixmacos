package dev.viasix.app.session

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SessionRecoverySurfaceTest {
    @Test
    fun activityRestoresRuntimeNavigationPendingConsentAndWarmIntents() {
        val activity =
            resolve(
                "src/main/java/dev/viasix/app/MainActivity.kt",
                "app/src/main/java/dev/viasix/app/MainActivity.kt",
            ).readText()
        val tile =
            resolve(
                "src/main/java/dev/viasix/app/tile/ViaSixTileService.kt",
                "app/src/main/java/dev/viasix/app/tile/ViaSixTileService.kt",
            ).readText()
        val service =
            resolve(
                "src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
                "app/src/main/java/dev/viasix/app/vpn/ViaSixVpnService.kt",
            ).readText()
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

        assertTrue(activity.contains("SessionRuntimeStore(this)"))
        assertTrue(activity.contains("initialRuntime.toUiSnapshot()"))
        assertTrue(activity.contains("AppSection.parse(initialPrefs.selectedSection)"))
        assertTrue(activity.contains("override fun onSaveInstanceState"))
        assertTrue(activity.contains("STATE_PENDING_VPN_START_REASON"))
        assertTrue(activity.contains("STATE_PENDING_NOTIFICATION_START_REASON"))
        assertTrue(activity.contains("override fun onNewIntent"))
        assertTrue(activity.contains("onLaunchIntent?.invoke(intent)"))
        assertTrue(activity.contains("currentVpnPermissionState()"))
        assertTrue(activity.contains("Settings.ACTION_VPN_SETTINGS"))
        assertTrue(activity.contains("onRefreshVpnPermission?.invoke()"))
        assertTrue(activity.contains("PowerManager::class.java"))
        assertTrue(activity.contains("Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS"))
        assertTrue(activity.contains("onRefreshBatteryOptimization?.invoke()"))
        assertTrue(tile.contains("Intent.FLAG_ACTIVITY_CLEAR_TOP"))
        assertTrue(tile.contains("Intent.FLAG_ACTIVITY_SINGLE_TOP"))
        assertTrue(service.contains("Intent.FLAG_ACTIVITY_CLEAR_TOP"))
        assertTrue(service.contains("Intent.FLAG_ACTIVITY_SINGLE_TOP"))
        assertTrue(service.contains("SessionPrefsStore(this).load()"))
        assertTrue(service.contains("VpnStartOrigin.detect"))
        assertTrue(service.contains("startOrigin.restoreSavedSession"))
        assertTrue(commands.contains(".setAction(VpnStartOrigin.ACTION_START)"))
        assertTrue(service.contains("override fun onRevoke"))
        assertTrue(service.contains("RuntimeStackHealth.failure"))
        assertTrue(service.contains("RuntimeProcessIdentity.token"))
        assertTrue(prefs.contains(".put(\"selectedSection\", selectedSection)"))
        assertTrue(prefs.contains("o.optString(\"selectedSection\", \"overview\")"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
