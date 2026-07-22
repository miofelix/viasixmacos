package dev.viasix.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import dev.viasix.app.MainActivity
import dev.viasix.app.mihomo.MihomoInstaller
import dev.viasix.app.mihomo.MihomoProcess
import dev.viasix.core.projection.MihomoProjection
import dev.viasix.core.projection.ProjectError
import dev.viasix.core.projection.ProjectOptions
import dev.viasix.core.projection.RoutingMode
import java.io.File
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Android network path: projects profile → starts mihomo → establishes a VPN
 * session that publishes an HTTP/HTTPS proxy (API 29+) for apps using the VPN
 * network. Full packet TUN into mihomo is a later step.
 */
class ViaSixVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null
    private var mihomo: MihomoProcess? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutdownAll("stopped by user")
            return START_NOT_STICKY
        }

        val profile = intent?.getStringExtra(EXTRA_PROFILE).orEmpty()
        val selectedIp = intent?.getStringExtra(EXTRA_SELECTED_IP)
        val modeWire = intent?.getStringExtra(EXTRA_MODE) ?: "rule"
        val mode = RoutingMode.parse(modeWire) ?: RoutingMode.RULE

        startForeground(NOTIFICATION_ID, buildNotification("Starting ViaSix…"))

        thread(name = "viasix-vpn-start", isDaemon = true) {
            try {
                startStack(profile, selectedIp, mode)
            } catch (error: Exception) {
                Log.e(TAG, "start failed", error)
                updateNotification("Start failed: ${error.message}")
                shutdownAll("start failed")
            }
        }
        return START_STICKY
    }

    private fun startStack(profile: String, selectedIp: String?, mode: RoutingMode) {
        val secret = UUID.randomUUID().toString().replace("-", "")
        val options =
            ProjectOptions(
                routingMode = mode,
                selectedAddress = if (mode == RoutingMode.DIRECT) null else selectedIp,
                listenAddress = "127.0.0.1",
                mixedPort = MIXED_PORT,
                controllerPort = CONTROLLER_PORT,
                controllerSecret = secret,
            )

        val yaml =
            try {
                MihomoProjection.projectYaml(
                    if (mode == RoutingMode.DIRECT) null else profile,
                    options,
                )
            } catch (error: ProjectError) {
                throw IllegalArgumentException("projection: ${error.contractCode}", error)
            }

        val binary = MihomoInstaller.installIfNeeded(this)
        val workDir = File(filesDir, "mihomo-runtime")
        val process = MihomoProcess(binary, workDir)
        process.start(yaml)
        mihomo = process

        // VPN session for system integration + HTTP proxy (Q+).
        // Intentionally avoid 0.0.0.0/0 routes until packet path is implemented,
        // so we don't black-hole traffic when mihomo is only a local mixed proxy.
        val builder =
            Builder()
                .setSession("ViaSix")
                .setMtu(1500)
                .addAddress("10.10.0.2", 32)
                .addDnsServer("1.1.1.1")
                .addDisallowedApplication(packageName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(
                    "127.0.0.1",
                    MIXED_PORT,
                    listOf("localhost", "127.0.0.1", "::1"),
                ),
            )
        }

        tunnel?.close()
        tunnel = builder.establish()
            ?: throw IllegalStateException("VpnService.Builder.establish() returned null")

        updateNotification("Mihomo running · mixed 127.0.0.1:$MIXED_PORT")
        Log.i(TAG, "stack ready; controller 127.0.0.1:$CONTROLLER_PORT")
    }

    override fun onDestroy() {
        shutdownAll("destroyed")
        super.onDestroy()
    }

    private fun shutdownAll(reason: String) {
        Log.i(TAG, "shutdown: $reason")
        try {
            mihomo?.stop()
        } catch (error: Exception) {
            Log.w(TAG, "mihomo stop: ${error.message}")
        }
        mihomo = null
        try {
            tunnel?.close()
        } catch (_: Exception) {
        }
        tunnel = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun updateNotification(content: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(content))
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
        const val EXTRA_PROFILE = "profile"
        const val EXTRA_SELECTED_IP = "selected_ip"
        const val EXTRA_MODE = "mode"
        const val MIXED_PORT = 11451
        const val CONTROLLER_PORT = 9090

        private const val CHANNEL_ID = "viasix_vpn"
        private const val NOTIFICATION_ID = 42
        private const val TAG = "ViaSixVpnService"
    }
}
