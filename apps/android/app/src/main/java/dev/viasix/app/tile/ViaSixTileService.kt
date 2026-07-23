package dev.viasix.app.tile

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import dev.viasix.app.MainActivity
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
        val running = VpnSessionCommands.isRuntimeRunning(this)
        if (running) {
            startService(VpnSessionCommands.buildStopIntent(this))
            // Optimistic inactive until prefs catch up
            qsTile?.state = Tile.STATE_INACTIVE
            qsTile?.subtitle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "正在断开…" else null
            qsTile?.updateTile()
            return
        }

        when (val action = VpnSessionCommands.prepareStart(this, reason = "quick-settings")) {
            is VpnSessionCommands.StartAction.StartService -> {
                startForegroundService(action.intent)
                qsTile?.state = Tile.STATE_ACTIVE
                qsTile?.subtitle =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "正在连接…" else null
                qsTile?.updateTile()
            }
            is VpnSessionCommands.StartAction.NeedsVpnConsent -> {
                // Collapse panel and open the app to complete VPN consent + start.
                val launch =
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        .putExtra(VpnSessionCommands.EXTRA_REQUEST_START, true)
                collapseAndLaunch(launch)
            }
            is VpnSessionCommands.StartAction.Blocked -> {
                val launch =
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        .putExtra(EXTRA_GATE_MESSAGE, action.gate.message)
                        .putExtra(EXTRA_GATE_SECTION, action.gate.sectionWire)
                collapseAndLaunch(launch)
            }
        }
    }

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
                @Suppress("DEPRECATION")
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
        val running = VpnSessionCommands.isRuntimeRunning(this)
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "ViaSix"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (running) "已连接 · 点按断开" else "点按连接"
        }
        tile.contentDescription =
            if (running) {
                "ViaSix 已连接，点按断开"
            } else {
                "ViaSix 未连接，点按连接"
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
