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
import dev.viasix.app.mihomo.ControllerClient
import dev.viasix.app.mihomo.MihomoInstaller
import dev.viasix.app.mihomo.MihomoProcess
import dev.viasix.app.tun.Tun2SocksEngine
import dev.viasix.core.projection.MihomoProjection
import dev.viasix.core.projection.ProjectError
import dev.viasix.core.projection.ProjectOptions
import dev.viasix.core.projection.RoutingMode
import java.io.File
import java.util.UUID
import kotlin.concurrent.thread

/**
 * Full-path Android network access:
 * 1) Project profile → start user-space mihomo (mixed/SOCKS on loopback)
 * 2) Establish VPN with default routes
 * 3) Exclude this app UID from the VPN (prevents routing loops for mihomo)
 * 4) Userspace IPv4 TCP→SOCKS + DNS forwarder (Tun2SocksEngine)
 */
class ViaSixVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null
    private var mihomo: MihomoProcess? = null
    private var tunEngine: Tun2SocksEngine? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutdownAll("stopped by user")
            return START_NOT_STICKY
        }

        val profile = intent?.getStringExtra(EXTRA_PROFILE).orEmpty()
        val selectedIp = intent?.getStringExtra(EXTRA_SELECTED_IP)
        val modeWire = intent?.getStringExtra(EXTRA_MODE) ?: "rule"
        val mode = RoutingMode.parse(modeWire) ?: RoutingMode.RULE
        val fullTunnel = intent?.getBooleanExtra(EXTRA_FULL_TUNNEL, true) ?: true

        startForeground(NOTIFICATION_ID, buildNotification("Starting ViaSix…"))

        thread(name = "viasix-vpn-start", isDaemon = true) {
            try {
                startStack(profile, selectedIp, mode, fullTunnel)
            } catch (error: Exception) {
                Log.e(TAG, "start failed", error)
                updateNotification("Start failed: ${error.message}")
                shutdownAll("start failed")
            }
        }
        return START_STICKY
    }

    private fun startStack(
        profile: String,
        selectedIp: String?,
        mode: RoutingMode,
        fullTunnel: Boolean,
    ) {
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

        // Give controller a moment, then verify and persist runtime status for the UI.
        ControllerClient.sleepQuietly(400)
        val health = ControllerClient.probe("127.0.0.1", CONTROLLER_PORT, secret)
        writeRuntimeStatus(
            running = process.isRunning,
            healthMessage = health.message,
            secret = secret,
        )
        if (!health.ok) {
            Log.w(TAG, "controller not healthy yet: ${health.message}")
        }

        // Exclude our UID so mihomo outbound sockets use the underlying network
        // instead of looping into this VPN interface.
        val builder =
            Builder()
                .setSession("ViaSix")
                .setMtu(1500)
                .addAddress("10.10.0.2", 32)
                .addDnsServer("1.1.1.1")
                .addDisallowedApplication(packageName)

        if (fullTunnel) {
            builder.addRoute("0.0.0.0", 0)
            // IPv6 default route needs an IPv6 address on the interface.
            try {
                builder.addAddress("fd00:10:10::2", 128)
                builder.addRoute("::", 0)
            } catch (error: Exception) {
                Log.w(TAG, "IPv6 route not applied: ${error.message}")
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Also publish proxy metadata for proxy-aware apps.
            builder.setHttpProxy(
                android.net.ProxyInfo.buildDirectProxy(
                    "127.0.0.1",
                    MIXED_PORT,
                    listOf("localhost", "127.0.0.1", "::1"),
                ),
            )
        }

        tunnel?.close()
        val established =
            builder.establish()
                ?: throw IllegalStateException("VpnService.Builder.establish() returned null")
        tunnel = established

        if (fullTunnel) {
            val engine =
                Tun2SocksEngine(
                    vpnService = this,
                    tun = established,
                    socksHost = "127.0.0.1",
                    socksPort = MIXED_PORT,
                )
            engine.start()
            tunEngine = engine
            updateNotification(
                if (health.ok) {
                    "Full tunnel · mixed :$MIXED_PORT · ${health.version ?: "ok"}"
                } else {
                    "Full tunnel · mixed :$MIXED_PORT · controller warming"
                },
            )
        } else {
            updateNotification(
                if (health.ok) {
                    "Proxy VPN · mixed :$MIXED_PORT · ${health.version ?: "ok"}"
                } else {
                    "Proxy VPN · mixed :$MIXED_PORT · controller warming"
                },
            )
        }
        Log.i(TAG, "stack ready fullTunnel=$fullTunnel health=${health.message}")
    }

    override fun onDestroy() {
        shutdownAll("destroyed")
        super.onDestroy()
    }

    private fun shutdownAll(reason: String) {
        Log.i(TAG, "shutdown: $reason")
        try {
            tunEngine?.stop()
        } catch (error: Exception) {
            Log.w(TAG, "tun stop: ${error.message}")
        }
        tunEngine = null
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
        writeRuntimeStatus(running = false, healthMessage = "stopped", secret = "")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun writeRuntimeStatus(running: Boolean, healthMessage: String, secret: String) {
        getSharedPreferences(RUNTIME_PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RUNNING, running)
            .putString(KEY_HEALTH, healthMessage)
            .putString(KEY_SECRET, secret)
            .putInt(KEY_CONTROLLER_PORT, CONTROLLER_PORT)
            .putInt(KEY_MIXED_PORT, MIXED_PORT)
            .apply()
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
        const val EXTRA_FULL_TUNNEL = "full_tunnel"
        const val MIXED_PORT = 11451
        const val CONTROLLER_PORT = 9090
        const val RUNTIME_PREFS = "viasix_runtime"
        const val KEY_RUNNING = "running"
        const val KEY_HEALTH = "health"
        const val KEY_SECRET = "secret"
        const val KEY_CONTROLLER_PORT = "controllerPort"
        const val KEY_MIXED_PORT = "mixedPort"

        private const val CHANNEL_ID = "viasix_vpn"
        private const val NOTIFICATION_ID = 42
        private const val TAG = "ViaSixVpnService"
    }
}
