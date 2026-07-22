package dev.viasix.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import dev.viasix.app.MainActivity

/**
 * Android virtual-network path (product counterpart of desktop TUN).
 *
 * MVP scaffold: creates a VpnService session and foreground notification.
 * Embedding mihomo + packet plumbing lands in a follow-up change.
 */
class ViaSixVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopTunnel()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification("ViaSix VPN scaffold running"))
        if (tunnel == null) {
            try {
                tunnel =
                    Builder()
                        .setSession("ViaSix")
                        .addAddress("10.0.0.2", 32)
                        .addRoute("0.0.0.0", 0)
                        // Keep DNS out of this scaffold; real path will inject mihomo DNS.
                        .setMtu(1500)
                        .establish()
                Log.i(TAG, "VPN interface established (scaffold)")
            } catch (error: Exception) {
                Log.e(TAG, "Failed to establish VPN", error)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    private fun stopTunnel() {
        try {
            tunnel?.close()
        } catch (_: Exception) {
        }
        tunnel = null
    }

    private fun buildNotification(content: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    "ViaSix VPN",
                    NotificationManager.IMPORTANCE_LOW,
                )
            manager.createNotificationChannel(channel)
        }
        val launch =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE,
            )
        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        return builder
            .setContentTitle("ViaSix")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STOP = "dev.viasix.app.vpn.STOP"
        private const val CHANNEL_ID = "viasix_vpn"
        private const val NOTIFICATION_ID = 42
        private const val TAG = "ViaSixVpnService"
    }
}
