package dev.viasix.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.service.quicksettings.TileService
import android.util.Log
import dev.viasix.app.MainActivity
import dev.viasix.app.R
import dev.viasix.app.mihomo.ControllerClient
import dev.viasix.app.mihomo.MihomoInstaller
import dev.viasix.app.mihomo.MihomoProcess
import dev.viasix.app.mihomo.TrafficSampler
import dev.viasix.app.tile.ViaSixTileService
import dev.viasix.app.tun.Tun2SocksEngine
import dev.viasix.core.formatting.ByteRateFormatter
import dev.viasix.core.projection.MihomoProjection
import dev.viasix.core.projection.ProjectError
import dev.viasix.core.projection.ProjectOptions
import dev.viasix.core.projection.RoutingMode
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Full-path Android network access:
 * 1) Project profile → start user-space mihomo (mixed/SOCKS on loopback)
 * 2) Establish VPN with default routes (IPv4 + IPv6 when full tunnel)
 * 3) Exclude this app UID from the VPN (prevents routing loops for mihomo)
 * 4) Userspace IPv4/IPv6 TCP→SOCKS CONNECT + general UDP→per-client SOCKS UDP ASSOCIATE
 *    ([Tun2SocksEngine]); DNS/53 always uses protected per-query DatagramSocket
 *
 * Supports restart with new profile/node without leaving a half-live stack.
 * Emits a circular event log into SharedPreferences for the UI log pane.
 */
class ViaSixVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null
    private var mihomo: MihomoProcess? = null
    private var tunEngine: Tun2SocksEngine? = null
    private val starting = AtomicBoolean(false)
    private val trafficSampler = TrafficSampler(maxHistory = 30)
    private val trafficLoopRunning = AtomicBoolean(false)
    private var trafficThread: Thread? = null
    private var activeSecret: String = ""

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            appendEvent("用户停止会话", "info")
            shutdownAll("stopped by user", stopService = true)
            return START_NOT_STICKY
        }

        val profile = intent?.getStringExtra(EXTRA_PROFILE).orEmpty()
        val selectedIp = intent?.getStringExtra(EXTRA_SELECTED_IP)
        val modeWire = intent?.getStringExtra(EXTRA_MODE) ?: "rule"
        val mode = RoutingMode.parse(modeWire) ?: RoutingMode.RULE
        val fullTunnel = intent?.getBooleanExtra(EXTRA_FULL_TUNNEL, true) ?: true
        val reason = intent?.getStringExtra(EXTRA_REASON).orEmpty().ifBlank { "start" }

        startForeground(NOTIFICATION_ID, buildNotification("Starting ViaSix…"))
        appendEvent("启动请求（$reason） mode=${mode.wire} fullTunnel=$fullTunnel", "info")

        if (!starting.compareAndSet(false, true)) {
            appendEvent("已有启动任务进行中，忽略重复请求", "warning")
            return START_STICKY
        }

        thread(name = "viasix-vpn-start", isDaemon = true) {
            try {
                // Tear down any previous stack before applying new parameters
                // (node apply / reconnect path).
                stopStackOnly("restart for $reason")
                startStack(profile, selectedIp, mode, fullTunnel)
            } catch (error: Exception) {
                Log.e(TAG, "start failed", error)
                appendEvent("启动失败：${error.message}", "error")
                updateNotification("Start failed: ${error.message}")
                shutdownAll("start failed", stopService = true)
            } finally {
                starting.set(false)
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

        appendEvent("投影完成，启动 mihomo…", "info")
        val binary = MihomoInstaller.installIfNeeded(this)
        val workDir = File(filesDir, "mihomo-runtime")
        val process = MihomoProcess(binary, workDir)
        process.start(yaml)
        mihomo = process

        ControllerClient.sleepQuietly(400)
        val health = ControllerClient.probe("127.0.0.1", CONTROLLER_PORT, secret)
        val startedAt = System.currentTimeMillis()
        writeRuntimeStatus(
            running = process.isRunning,
            healthMessage = health.message,
            secret = secret,
            version = health.version,
            startedAt = startedAt,
        )
        if (!health.ok) {
            Log.w(TAG, "controller not healthy yet: ${health.message}")
            appendEvent("控制器尚未就绪：${health.message}", "warning")
        } else {
            appendEvent("控制器就绪 ${health.version ?: ""}".trim(), "success")
        }

        val builder =
            Builder()
                .setSession("ViaSix")
                .setMtu(1500)
                .addAddress("10.10.0.2", 32)
                .addDnsServer("1.1.1.1")
                .addDisallowedApplication(packageName)

        if (fullTunnel) {
            builder.addRoute("0.0.0.0", 0)
            try {
                builder.addAddress("fd00:10:10::2", 128)
                builder.addRoute("::", 0)
            } catch (error: Exception) {
                Log.w(TAG, "IPv6 route not applied: ${error.message}")
                appendEvent("IPv6 默认路由未应用：${error.message}", "warning")
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setHttpProxy(
                android.net.ProxyInfo.buildDirectProxy(
                    "127.0.0.1",
                    MIXED_PORT,
                    listOf("localhost", "127.0.0.1", "::1"),
                ),
            )
        }

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
                    "全量隧道 · mixed :$MIXED_PORT · ${health.version ?: "ok"}"
                } else {
                    "全量隧道 · mixed :$MIXED_PORT · 控制器预热中"
                },
            )
            appendEvent("全量隧道已建立（TCP/UDP IPv4/IPv6 → SOCKS）", "success")
        } else {
            updateNotification(
                if (health.ok) {
                    "代理 VPN · mixed :$MIXED_PORT · ${health.version ?: "ok"}"
                } else {
                    "代理 VPN · mixed :$MIXED_PORT · 控制器预热中"
                },
            )
            appendEvent("HTTP 代理 VPN 会话已建立（无默认路由）", "success")
        }
        activeSecret = secret
        startTrafficNotificationLoop(secret)
        Log.i(TAG, "stack ready fullTunnel=$fullTunnel health=${health.message}")
    }

    /** Clash-style live rates in the ongoing VPN notification. */
    private fun startTrafficNotificationLoop(secret: String) {
        stopTrafficNotificationLoop()
        trafficSampler.reset()
        trafficLoopRunning.set(true)
        trafficThread =
            thread(name = "viasix-vpn-traffic", isDaemon = true) {
                while (trafficLoopRunning.get()) {
                    try {
                        val snap = trafficSampler.sample("127.0.0.1", CONTROLLER_PORT, secret)
                        if (snap.live) {
                            val line =
                                "↑ ${ByteRateFormatter.formatCompactRate(snap.upBps)}  " +
                                    "↓ ${ByteRateFormatter.formatCompactRate(snap.downBps)}  ·  " +
                                    "conn ${snap.connectionCount}"
                            updateNotification(line)
                        }
                    } catch (error: Exception) {
                        Log.w(TAG, "traffic sample: ${error.message}")
                    }
                    try {
                        Thread.sleep(TRAFFIC_POLL_MS)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
    }

    private fun stopTrafficNotificationLoop() {
        trafficLoopRunning.set(false)
        try {
            trafficThread?.interrupt()
        } catch (_: Exception) {
        }
        trafficThread = null
        trafficSampler.reset()
    }

    override fun onDestroy() {
        shutdownAll("destroyed", stopService = false)
        super.onDestroy()
    }

    /** Stop engines/process but keep the service if a restart is about to begin. */
    private fun stopStackOnly(reason: String) {
        Log.i(TAG, "stop stack: $reason")
        stopTrafficNotificationLoop()
        activeSecret = ""
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
    }

    private fun shutdownAll(reason: String, stopService: Boolean) {
        Log.i(TAG, "shutdown: $reason")
        stopStackOnly(reason)
        writeRuntimeStatus(
            running = false,
            healthMessage = "stopped",
            secret = "",
            version = null,
            startedAt = null,
        )
        appendEvent("会话结束：$reason", "info")
        if (stopService) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun writeRuntimeStatus(
        running: Boolean,
        healthMessage: String,
        secret: String,
        version: String?,
        startedAt: Long?,
    ) {
        getSharedPreferences(RUNTIME_PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_RUNNING, running)
            .putString(KEY_HEALTH, healthMessage)
            .putString(KEY_SECRET, secret)
            .putInt(KEY_CONTROLLER_PORT, CONTROLLER_PORT)
            .putInt(KEY_MIXED_PORT, MIXED_PORT)
            .putString(KEY_VERSION, version.orEmpty())
            .putLong(KEY_STARTED_AT, startedAt ?: 0L)
            .apply()
        notifyTileRefresh()
    }

    /** Keep the Quick Settings tile in sync with VPN runtime (no polling required). */
    private fun notifyTileRefresh() {
        try {
            TileService.requestListeningState(
                this,
                ComponentName(this, ViaSixTileService::class.java),
            )
        } catch (error: Exception) {
            Log.w(TAG, "tile refresh: ${error.message}")
        }
    }

    private fun appendEvent(message: String, level: String) {
        try {
            val prefs = getSharedPreferences(RUNTIME_PREFS, MODE_PRIVATE)
            val existing = prefs.getString(KEY_EVENTS, "[]") ?: "[]"
            val array =
                try {
                    JSONArray(existing)
                } catch (_: Exception) {
                    JSONArray()
                }
            val entry =
                JSONObject()
                    .put("ts", TIME_FORMAT.format(Date()))
                    .put("level", level)
                    .put("message", message)
                    .put("id", System.currentTimeMillis())
            // newest first
            val next = JSONArray()
            next.put(entry)
            val limit = 100
            for (i in 0 until minOf(array.length(), limit - 1)) {
                next.put(array.get(i))
            }
            prefs.edit().putString(KEY_EVENTS, next.toString()).apply()
        } catch (error: Exception) {
            Log.w(TAG, "appendEvent failed: ${error.message}")
        }
    }

    private fun updateNotification(content: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(content))
    }

    private fun buildNotification(content: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "ViaSix VPN",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "ViaSix 连接状态、实时速率与会话控制"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
        manager.createNotificationChannel(channel)
        val launch =
            PendingIntent.getActivity(
                this,
                REQUEST_OPEN_APP,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE,
            )
        val disconnect =
            PendingIntent.getService(
                this,
                REQUEST_DISCONNECT,
                Intent(this, ViaSixVpnService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val disconnectAction =
            Notification.Action.Builder(
                Icon.createWithResource(this, R.drawable.ic_viasix_notification),
                "断开",
                disconnect,
            ).build()
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("ViaSix")
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_viasix_notification)
            .setColor(0xFF007AFF.toInt())
            .setContentIntent(launch)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .addAction(disconnectAction)
            .build()
    }

    companion object {
        const val ACTION_STOP = "dev.viasix.app.vpn.STOP"
        const val EXTRA_PROFILE = "profile"
        const val EXTRA_SELECTED_IP = "selected_ip"
        const val EXTRA_MODE = "mode"
        const val EXTRA_FULL_TUNNEL = "full_tunnel"
        const val EXTRA_REASON = "reason"
        const val MIXED_PORT = 11451
        const val CONTROLLER_PORT = 9090
        const val RUNTIME_PREFS = "viasix_runtime"
        const val KEY_RUNNING = "running"
        const val KEY_HEALTH = "health"
        const val KEY_SECRET = "secret"
        const val KEY_CONTROLLER_PORT = "controllerPort"
        const val KEY_MIXED_PORT = "mixedPort"
        const val KEY_VERSION = "version"
        const val KEY_STARTED_AT = "startedAt"
        const val KEY_EVENTS = "events"

        private val TIME_FORMAT = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        private const val CHANNEL_ID = "viasix_vpn"
        private const val NOTIFICATION_ID = 42
        private const val REQUEST_OPEN_APP = 43
        private const val REQUEST_DISCONNECT = 44
        private const val TRAFFIC_POLL_MS = 1_500L
        private const val TAG = "ViaSixVpnService"
    }
}
