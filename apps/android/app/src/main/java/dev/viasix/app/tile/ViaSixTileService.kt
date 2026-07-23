package dev.viasix.app.tile

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import dev.viasix.app.MainActivity
import dev.viasix.app.session.ConnectionPhase
import dev.viasix.app.session.NotificationPermissionFlow
import dev.viasix.app.session.NotificationPermissionState
import dev.viasix.app.session.POST_NOTIFICATIONS_PERMISSION
import dev.viasix.app.session.VpnSessionCommands

/**
 * Quick Settings tile — Clash Meta / NekoBox style one-tap connect/disconnect.
 * Uses the same session prefs + start gates as the in-app Overview control.
 */
class ViaSixTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val phase = VpnSessionCommands.runtimePhase(this)
        if (phase.isActiveOrTransitioning) {
            startService(VpnSessionCommands.buildStopIntent(this))
            // Optimistic inactive until prefs catch up
            qsTile?.state = Tile.STATE_INACTIVE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                qsTile?.subtitle = "正在断开…"
            }
            qsTile?.updateTile()
            return
        }

        val prefs = VpnSessionCommands.loadPrefs(this)
        when (
            val action =
                VpnSessionCommands.prepareStart(
                    this,
                    prefs = prefs,
                    reason = "quick-settings",
                )
        ) {
            is VpnSessionCommands.StartAction.StartService -> {
                val notificationState =
                    NotificationPermissionState(
                        required = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                        granted =
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                                checkSelfPermission(POST_NOTIFICATIONS_PERMISSION) ==
                                PackageManager.PERMISSION_GRANTED,
                        wasRequested = prefs.notificationPermissionRequested,
                    )
                if (
                    NotificationPermissionFlow.beforeStart(notificationState) ==
                    NotificationPermissionFlow.BeforeStart.REQUEST_PERMISSION
                ) {
                    openAppForStart()
                    return
                }
                startForegroundService(action.intent)
                qsTile?.state = Tile.STATE_ACTIVE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    qsTile?.subtitle = "正在连接…"
                }
                qsTile?.updateTile()
            }
            is VpnSessionCommands.StartAction.NeedsVpnConsent -> {
                // Collapse panel and open the app to complete VPN consent + start.
                openAppForStart()
            }
            is VpnSessionCommands.StartAction.Blocked -> {
                val launch =
                    buildAppLaunchIntent()
                        .putExtra(EXTRA_GATE_MESSAGE, action.gate.message)
                        .putExtra(EXTRA_GATE_SECTION, action.gate.sectionWire)
                collapseAndLaunch(launch)
            }
        }
    }

    private fun openAppForStart() {
        val launch =
            buildAppLaunchIntent()
                .putExtra(VpnSessionCommands.EXTRA_REQUEST_START, true)
        collapseAndLaunch(launch)
    }

    private fun buildAppLaunchIntent(): Intent =
        Intent(this, MainActivity::class.java)
            .addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )

    @Suppress("DEPRECATION")
    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun collapseAndLaunch(intent: Intent) {
        val pending =
            PendingIntent.getActivity(
                this,
                REQUEST_LAUNCH,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startActivityAndCollapse(pending)
            } else {
                startActivityAndCollapse(intent)
            }
        } catch (error: Exception) {
            Log.w(TAG, "tile launch failed: ${error.message}")
            try {
                startActivity(intent)
            } catch (inner: Exception) {
                Log.w(TAG, "tile startActivity failed: ${inner.message}")
            }
        }
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val phase = VpnSessionCommands.runtimePhase(this)
        tile.state =
            if (phase == ConnectionPhase.RUNNING || phase == ConnectionPhase.STARTING) {
                Tile.STATE_ACTIVE
            } else {
                Tile.STATE_INACTIVE
            }
        tile.label = "ViaSix"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle =
                when (phase) {
                    ConnectionPhase.STARTING -> "正在连接 · 点按取消"
                    ConnectionPhase.RUNNING -> "已连接 · 点按断开"
                    ConnectionPhase.STOPPING -> "正在断开…"
                    ConnectionPhase.STOPPED -> "点按连接"
                }
        }
        tile.contentDescription =
            when (phase) {
                ConnectionPhase.STARTING -> "ViaSix 正在连接，点按取消"
                ConnectionPhase.RUNNING -> "ViaSix 已连接，点按断开"
                ConnectionPhase.STOPPING -> "ViaSix 正在断开"
                ConnectionPhase.STOPPED -> "ViaSix 未连接，点按连接"
            }
        tile.updateTile()
    }

    companion object {
        private const val TAG = "ViaSixTile"
        private const val REQUEST_LAUNCH = 71
        const val EXTRA_GATE_MESSAGE = "dev.viasix.app.TILE_GATE_MESSAGE"
        const val EXTRA_GATE_SECTION = "dev.viasix.app.TILE_GATE_SECTION"
    }
}
