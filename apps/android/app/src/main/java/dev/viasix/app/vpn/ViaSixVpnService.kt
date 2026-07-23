package dev.viasix.app.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.IpPrefix
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
import dev.viasix.app.prefs.SessionPrefsStore
import dev.viasix.app.session.AppRoutingMode
import dev.viasix.app.session.AppRoutingPolicy
import dev.viasix.app.session.DnsRoutingMode
import dev.viasix.app.session.DnsSettingsPolicy
import dev.viasix.app.session.LocalNetworkBypassPolicy
import dev.viasix.app.session.RuntimeProcessIdentity
import dev.viasix.app.session.RuntimeStackFailure
import dev.viasix.app.session.RuntimeStackHealth
import dev.viasix.app.session.VpnStartOrigin
import dev.viasix.app.session.VpnMtuPolicy
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
import java.net.InetAddress
import java.net.Inet6Address
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
 *    ([Tun2SocksEngine]); DNS uses SOCKS by default with an explicit protected-direct option
 *
 * Supports restart with new profile/node without leaving a half-live stack.
 * Emits a circular event log into SharedPreferences for the UI log pane.
 */
class ViaSixVpnService : VpnService() {
    private var tunnel: ParcelFileDescriptor? = null
    private var mihomo: MihomoProcess? = null
    private var tunEngine: Tun2SocksEngine? = null
    private val starting = AtomicBoolean(false)
    private val shuttingDown = AtomicBoolean(false)
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
        if (shuttingDown.get()) return START_NOT_STICKY

        val startOrigin =
            VpnStartOrigin.detect(
                intentPresent = intent != null,
                action = intent?.action,
            )
        val restoredPrefs =
            if (startOrigin.restoreSavedSession) SessionPrefsStore(this).load() else null
        val profile = intent?.getStringExtra(EXTRA_PROFILE) ?: restoredPrefs?.profileYaml.orEmpty()
        val selectedIp =
            intent?.getStringExtra(EXTRA_SELECTED_IP) ?: restoredPrefs?.selectedAddress
        val modeWire = intent?.getStringExtra(EXTRA_MODE) ?: restoredPrefs?.routingMode ?: "rule"
        val mode = RoutingMode.parse(modeWire) ?: RoutingMode.RULE
        val fullTunnel =
            intent?.getBooleanExtra(EXTRA_FULL_TUNNEL, restoredPrefs?.fullTunnel ?: true)
                ?: restoredPrefs?.fullTunnel
                ?: true
        val vpnMtuInput =
            intent?.getStringExtra(EXTRA_VPN_MTU)
                ?: restoredPrefs?.vpnMtu
                ?: VpnMtuPolicy.DEFAULT.toString()
        val vpnMetered =
            intent?.getBooleanExtra(EXTRA_VPN_METERED, restoredPrefs?.vpnMetered ?: true)
                ?: restoredPrefs?.vpnMetered
                ?: true
        val bypassLocalNetwork =
            intent?.getBooleanExtra(
                EXTRA_BYPASS_LOCAL_NETWORK,
                restoredPrefs?.bypassLocalNetwork ?: false,
            ) ?: restoredPrefs?.bypassLocalNetwork ?: false
        val dnsRoutingMode =
            DnsRoutingMode.parse(
                intent?.getStringExtra(EXTRA_DNS_ROUTING_MODE)
                    ?: restoredPrefs?.dnsRoutingMode,
            )
        val dnsServerInput =
            intent?.getStringExtra(EXTRA_DNS_SERVER)
                ?: restoredPrefs?.dnsServer
                ?: DnsSettingsPolicy.DEFAULT_SERVER
        val appRoutingMode =
            AppRoutingMode.parse(
                intent?.getStringExtra(EXTRA_APP_ROUTING_MODE)
                    ?: restoredPrefs?.appRoutingMode,
            )
        val selectedAppPackages =
            intent?.getStringArrayListExtra(EXTRA_SELECTED_APP_PACKAGES)?.toList()
                ?: restoredPrefs?.selectedAppPackages
                ?: emptyList()
        val reason =
            intent?.getStringExtra(EXTRA_REASON).orEmpty().ifBlank {
                startOrigin.reason
            }

        startForeground(NOTIFICATION_ID, buildNotification("Starting ViaSix…"))
        appendEvent(
            "启动请求（$reason） mode=${mode.wire} fullTunnel=$fullTunnel mtu=$vpnMtuInput " +
                "metered=$vpnMetered " +
                "bypassLocal=$bypassLocalNetwork " +
                "appRouting=${appRoutingMode.wire} apps=${selectedAppPackages.size}",
            "info",
        )

        if (!starting.compareAndSet(false, true)) {
            appendEvent("已有启动任务进行中，忽略重复请求", "warning")
            return START_STICKY
        }

        thread(name = "viasix-vpn-start", isDaemon = true) {
            try {
                // Tear down any previous stack before applying new parameters
                // (node apply / reconnect path).
                stopStackOnly("restart for $reason")
                startStack(
                    profile,
                    selectedIp,
                    mode,
                    fullTunnel,
                    vpnMtuInput,
                    vpnMetered,
                    bypassLocalNetwork,
                    dnsRoutingMode,
                    dnsServerInput,
                    appRoutingMode,
                    selectedAppPackages,
                )
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
        vpnMtuInput: String,
        vpnMetered: Boolean,
        bypassLocalNetwork: Boolean,
        dnsRoutingMode: DnsRoutingMode,
        dnsServerInput: String,
        appRoutingMode: AppRoutingMode,
        selectedAppPackages: List<String>,
    ) {
        val vpnMtu =
            VpnMtuPolicy.normalize(vpnMtuInput)
                ?: throw IllegalArgumentException(
                    "VPN MTU must be ${VpnMtuPolicy.MIN}..${VpnMtuPolicy.MAX}: $vpnMtuInput",
                )
        val normalizedDnsServer = DnsSettingsPolicy.normalizeServer(dnsServerInput)
        if (fullTunnel && normalizedDnsServer == null) {
            throw IllegalArgumentException("invalid DNS server: $dnsServerInput")
        }
        val dnsServer = normalizedDnsServer ?: DnsSettingsPolicy.DEFAULT_SERVER
        val dnsAddress = InetAddress.getByName(dnsServer)
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
                .setMtu(vpnMtu)
                .addAddress("10.10.0.2", 32)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(vpnMetered)
        }
        applyAppRouting(builder, appRoutingMode, selectedAppPackages)

        if (fullTunnel) {
            builder.addRoute("0.0.0.0", 0)
            if (dnsAddress !is Inet6Address) {
                builder.addDnsServer(dnsServer)
            }
            applyLocalNetworkBypass(
                builder = builder,
                enabled = bypassLocalNetwork,
                prefixes = LocalNetworkBypassPolicy.IPV4_PREFIXES,
            )
            preserveDnsVpnRoute(
                builder = builder,
                enabled = bypassLocalNetwork && dnsAddress !is Inet6Address,
                dnsAddress = dnsAddress,
            )
            var ipv6RouteApplied = false
            try {
                builder.addAddress("fd00:10:10::2", 128)
                builder.addRoute("::", 0)
                ipv6RouteApplied = true
                if (dnsAddress is Inet6Address) {
                    builder.addDnsServer(dnsServer)
                }
            } catch (error: Exception) {
                if (dnsAddress is Inet6Address) {
                    throw IllegalStateException(
                        "IPv6 DNS requires an IPv6 VPN route: ${error.message}",
                        error,
                    )
                }
                Log.w(TAG, "IPv6 route not applied: ${error.message}")
                appendEvent("IPv6 默认路由未应用：${error.message}", "warning")
            }
            if (ipv6RouteApplied) {
                applyLocalNetworkBypass(
                    builder = builder,
                    enabled = bypassLocalNetwork,
                    prefixes = LocalNetworkBypassPolicy.IPV6_PREFIXES,
                )
                preserveDnsVpnRoute(
                    builder = builder,
                    enabled = bypassLocalNetwork && dnsAddress is Inet6Address,
                    dnsAddress = dnsAddress,
                )
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
        appendEvent("VPN MTU：$vpnMtu", "info")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appendEvent(
                "VPN 计费属性：${if (vpnMetered) "按流量计费" else "不计费"}",
                "info",
            )
        }
        if (bypassLocalNetwork && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appendEvent("局域网绕过：私网、链路本地与组播流量不进入 VPN", "info")
        }

        if (fullTunnel) {
            val engine =
                Tun2SocksEngine(
                    vpnService = this,
                    tun = established,
                    socksHost = "127.0.0.1",
                    socksPort = MIXED_PORT,
                    dnsRoutingMode = dnsRoutingMode,
                    dnsUpstream = dnsAddress,
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
            appendEvent(
                "DNS：$dnsServer · ${dnsRoutingMode.label}",
                "info",
            )
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
        startTrafficNotificationLoop(secret, fullTunnel)
        Log.i(TAG, "stack ready fullTunnel=$fullTunnel health=${health.message}")
    }

    private fun applyAppRouting(
        builder: Builder,
        mode: AppRoutingMode,
        selectedAppPackages: List<String>,
    ) {
        val rules = AppRoutingPolicy.rules(mode, selectedAppPackages, packageName)
        var allowedCount = 0
        rules.allowedPackages.forEach { selectedPackage ->
            try {
                builder.addAllowedApplication(selectedPackage)
                allowedCount += 1
            } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                appendEvent("已忽略不存在的应用：$selectedPackage", "warning")
            }
        }
        rules.disallowedPackages.forEach { selectedPackage ->
            try {
                builder.addDisallowedApplication(selectedPackage)
            } catch (_: android.content.pm.PackageManager.NameNotFoundException) {
                appendEvent("已忽略不存在的绕过应用：$selectedPackage", "warning")
            }
        }
        if (mode == AppRoutingMode.ONLY_SELECTED && allowedCount == 0) {
            throw IllegalArgumentException("仅代理所选应用模式没有可用应用")
        }
        appendEvent(
            when (mode) {
                AppRoutingMode.ALL -> "应用路由：所有应用"
                AppRoutingMode.BYPASS_SELECTED ->
                    "应用路由：绕过 ${rules.disallowedPackages.size - 1} 个所选应用"
                AppRoutingMode.ONLY_SELECTED -> "应用路由：仅代理 $allowedCount 个所选应用"
            },
            "info",
        )
    }

    /** Clash-style live rates in the ongoing VPN notification. */
    private fun startTrafficNotificationLoop(
        secret: String,
        fullTunnel: Boolean,
    ) {
        stopTrafficNotificationLoop()
        trafficSampler.reset()
        trafficLoopRunning.set(true)
        trafficThread =
            thread(name = "viasix-vpn-traffic", isDaemon = true) {
                while (trafficLoopRunning.get()) {
                    val failure =
                        RuntimeStackHealth.failure(
                            mihomoRunning = mihomo?.isRunning == true,
                            fullTunnel = fullTunnel,
                            tunnelRunning = tunEngine?.isRunning == true,
                        )
                    if (failure != null) {
                        val component =
                            when (failure) {
                                RuntimeStackFailure.MIHOMO_EXITED -> "mihomo"
                                RuntimeStackFailure.TUNNEL_EXITED -> "TUN 转发"
                            }
                        appendEvent("$component 异常退出，正在结束会话", "error")
                        shutdownAll("$component exited unexpectedly", stopService = true)
                        break
                    }
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

    override fun onRevoke() {
        appendEvent("系统撤销 VPN 权限", "warning")
        shutdownAll("vpn permission revoked", stopService = true)
        super.onRevoke()
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
        if (!shuttingDown.compareAndSet(false, true)) return
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

    private fun applyLocalNetworkBypass(
        builder: Builder,
        enabled: Boolean,
        prefixes: List<String>,
    ) {
        if (!enabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        prefixes.forEach { prefix ->
            val separator = prefix.lastIndexOf('/')
            require(separator > 0) { "invalid local-network prefix: $prefix" }
            val address = InetAddress.getByName(prefix.substring(0, separator))
            val prefixLength = prefix.substring(separator + 1).toInt()
            builder.excludeRoute(IpPrefix(address, prefixLength))
        }
    }

    private fun preserveDnsVpnRoute(
        builder: Builder,
        enabled: Boolean,
        dnsAddress: InetAddress,
    ) {
        if (!enabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        builder.addRoute(dnsAddress, if (dnsAddress is Inet6Address) 128 else 32)
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
            .putString(KEY_PROCESS_TOKEN, if (running) RuntimeProcessIdentity.token else "")
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

    @Synchronized
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
                    .put("ts", formatEventTime())
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

    private fun formatEventTime(): String =
        SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())

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
                Intent(this, MainActivity::class.java)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    ),
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
        const val EXTRA_VPN_MTU = "vpn_mtu"
        const val EXTRA_VPN_METERED = "vpn_metered"
        const val EXTRA_BYPASS_LOCAL_NETWORK = "bypass_local_network"
        const val EXTRA_DNS_ROUTING_MODE = "dns_routing_mode"
        const val EXTRA_DNS_SERVER = "dns_server"
        const val EXTRA_APP_ROUTING_MODE = "app_routing_mode"
        const val EXTRA_SELECTED_APP_PACKAGES = "selected_app_packages"
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
        const val KEY_PROCESS_TOKEN = "processToken"

        private const val CHANNEL_ID = "viasix_vpn"
        private const val NOTIFICATION_ID = 42
        private const val REQUEST_OPEN_APP = 43
        private const val REQUEST_DISCONNECT = 44
        private const val TRAFFIC_POLL_MS = 1_500L
        private const val TAG = "ViaSixVpnService"
    }
}
