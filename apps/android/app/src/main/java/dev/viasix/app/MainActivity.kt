package dev.viasix.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import dev.viasix.app.cfst.CfstInstaller
import dev.viasix.app.cfst.CfstRunOutcome
import dev.viasix.app.cfst.CfstRunner
import dev.viasix.app.mihomo.ControllerClient
import dev.viasix.app.mihomo.TrafficSampler
import dev.viasix.app.mihomo.TrafficSnapshot
import dev.viasix.app.net.ExitIPDetectionMode
import dev.viasix.app.net.ExitIPDetector
import dev.viasix.app.prefs.SessionPrefsStore
import dev.viasix.app.state.DelayTestState
import dev.viasix.app.state.LogLevel
import dev.viasix.app.state.LogSource
import dev.viasix.app.state.RuntimeSnapshot
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.state.appendLog
import dev.viasix.app.state.rememberCandidate
import dev.viasix.app.ui.AppSection
import dev.viasix.app.ui.ViaSixApp
import dev.viasix.app.vpn.ViaSixVpnService
import dev.viasix.core.net.Ipv6Address
import dev.viasix.core.projection.MihomoProjection
import dev.viasix.core.projection.ProjectError
import dev.viasix.core.projection.ProjectOptions
import dev.viasix.core.projection.RoutingMode
import dev.viasix.core.speedtest.SpeedTestParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray

class MainActivity : ComponentActivity() {
    private var pendingStart: Intent? = null
    private lateinit var prefsStore: SessionPrefsStore
    private val trafficSampler = TrafficSampler()
    private val cfstRunner = CfstRunner()
    private var lastImportedEventId: Long = 0L
    private var wasRunning: Boolean = false

    private val vpnPermission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == Activity.RESULT_OK) {
                pendingStart?.let { startForegroundService(it) }
            }
            pendingStart = null
        }

    private val openDocument =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri == null) return@registerForActivityResult
            try {
                val text =
                    contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                        .orEmpty()
                if (text.isNotBlank()) {
                    profileImportHandler?.invoke(text)
                }
            } catch (_: Exception) {
            }
        }

    private var profileImportHandler: ((String) -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefsStore = SessionPrefsStore(this)
        val initial = SessionUiState.fromPrefs(prefsStore.load())

        setContent {
            var state by remember { mutableStateOf(initial) }
            var selectedSection by remember { mutableStateOf(AppSection.OVERVIEW) }
            val scope = rememberCoroutineScope()

            fun persist(next: SessionUiState) {
                prefsStore.save(next.toPrefs())
            }

            fun update(transform: (SessionUiState) -> SessionUiState) {
                val next = transform(state)
                state = next
                persist(next)
            }

            fun logOnly(transform: (SessionUiState) -> SessionUiState) {
                // Runtime / log updates that should not thrash session prefs writes.
                state = transform(state)
            }

            profileImportHandler = { yaml ->
                update {
                    it.copy(profileYaml = yaml)
                        .appendLog("已导入配置（${yaml.length} 字符）", LogLevel.Success, LogSource.Proxy)
                }
            }

            LaunchedEffect(Unit) {
                while (true) {
                    val runtimePrefs =
                        getSharedPreferences(ViaSixVpnService.RUNTIME_PREFS, MODE_PRIVATE)
                    val running = runtimePrefs.getBoolean(ViaSixVpnService.KEY_RUNNING, false)
                    val health =
                        runtimePrefs.getString(ViaSixVpnService.KEY_HEALTH, "—") ?: "—"
                    val port =
                        runtimePrefs.getInt(
                            ViaSixVpnService.KEY_CONTROLLER_PORT,
                            ViaSixVpnService.CONTROLLER_PORT,
                        )
                    val mixed =
                        runtimePrefs.getInt(
                            ViaSixVpnService.KEY_MIXED_PORT,
                            ViaSixVpnService.MIXED_PORT,
                        )
                    val secret =
                        runtimePrefs.getString(ViaSixVpnService.KEY_SECRET, "") ?: ""
                    val version =
                        runtimePrefs.getString(ViaSixVpnService.KEY_VERSION, "")
                            ?.ifBlank { null }
                    val startedAt =
                        runtimePrefs.getLong(ViaSixVpnService.KEY_STARTED_AT, 0L)
                            .takeIf { it > 0 }

                    if (!running && wasRunning) {
                        trafficSampler.reset()
                    }
                    wasRunning = running

                    val traffic =
                        if (running && secret.isNotBlank()) {
                            withContext(Dispatchers.IO) {
                                trafficSampler.sample("127.0.0.1", port, secret)
                            }
                        } else {
                            TrafficSnapshot.Idle
                        }

                    // Merge VPN service events into UI logs (newest first, skip known).
                    val eventsRaw = runtimePrefs.getString(ViaSixVpnService.KEY_EVENTS, "[]")
                    val imported = mutableListOf<Triple<Long, String, LogLevel>>()
                    try {
                        val arr = JSONArray(eventsRaw)
                        for (i in 0 until arr.length()) {
                            val o = arr.getJSONObject(i)
                            val id = o.optLong("id", 0L)
                            if (id <= lastImportedEventId) continue
                            val level =
                                when (o.optString("level")) {
                                    "error" -> LogLevel.Error
                                    "success" -> LogLevel.Success
                                    "warning" -> LogLevel.Warning
                                    else -> LogLevel.Info
                                }
                            imported += Triple(id, o.optString("message"), level)
                        }
                        if (imported.isNotEmpty()) {
                            lastImportedEventId = imported.maxOf { it.first }
                        }
                    } catch (_: Exception) {
                    }

                    logOnly { current ->
                        var next =
                            current.copy(
                                runtime =
                                    RuntimeSnapshot(
                                        running = running,
                                        health = health,
                                        traffic = traffic,
                                        controllerPort = port,
                                        mixedPort = mixed,
                                        mihomoVersion = version,
                                        secretPresent = secret.isNotBlank(),
                                        startedAtMillis = startedAt,
                                    ),
                            )
                        // Import oldest-first so list stays newest-first after prepend.
                        imported.sortedBy { it.first }.forEach { (_, message, level) ->
                            next =
                                next.appendLog(
                                    message,
                                    level,
                                    LogSource.System,
                                )
                        }
                        next
                    }

                    kotlinx.coroutines.delay(1200)
                }
            }

            fun buildStartIntent(reason: String): Intent =
                Intent(this@MainActivity, ViaSixVpnService::class.java)
                    .putExtra(ViaSixVpnService.EXTRA_PROFILE, state.profileYaml)
                    .putExtra(ViaSixVpnService.EXTRA_SELECTED_IP, state.selectedAddress)
                    .putExtra(ViaSixVpnService.EXTRA_MODE, state.routingMode.wire)
                    .putExtra(ViaSixVpnService.EXTRA_FULL_TUNNEL, state.fullTunnel)
                    .putExtra(ViaSixVpnService.EXTRA_REASON, reason)

            fun startVpn(reason: String = "connect") {
                if (state.routingMode != RoutingMode.DIRECT && !state.selectedIsIpv6) {
                    update {
                        it.appendLog(
                            "无法连接：请先选择合法 IPv6 节点",
                            LogLevel.Error,
                            LogSource.Node,
                            asNotice = true,
                        )
                    }
                    selectedSection = AppSection.NODES
                    return
                }
                if (state.routingMode != RoutingMode.DIRECT &&
                    state.profileSummary.primary == null
                ) {
                    update {
                        it.appendLog(
                            "无法连接：连接配置缺少有效代理入口",
                            LogLevel.Error,
                            LogSource.Proxy,
                            asNotice = true,
                        )
                    }
                    selectedSection = AppSection.PROFILES
                    return
                }

                val intent = buildStartIntent(reason)
                val prepare = VpnService.prepare(this@MainActivity)
                if (prepare != null) {
                    pendingStart = intent
                    vpnPermission.launch(prepare)
                    update {
                        it.appendLog("请求 VPN 权限…", LogLevel.Info, LogSource.Network)
                    }
                } else {
                    trafficSampler.reset()
                    startForegroundService(intent)
                    update {
                        it.appendLog("正在启动 VPN + mihomo…", LogLevel.Info, LogSource.Session)
                    }
                }
            }

            fun stopVpn() {
                startService(
                    Intent(this@MainActivity, ViaSixVpnService::class.java)
                        .setAction(ViaSixVpnService.ACTION_STOP),
                )
                trafficSampler.reset()
                update { it.appendLog("已发送停止意图", LogLevel.Info, LogSource.Session) }
            }

            fun projectPreview() {
                try {
                    val preview =
                        MihomoProjection.projectYaml(
                            if (state.routingMode == RoutingMode.DIRECT) null else state.profileYaml,
                            ProjectOptions(
                                routingMode = state.routingMode,
                                selectedAddress =
                                    if (state.routingMode == RoutingMode.DIRECT) {
                                        null
                                    } else {
                                        state.selectedAddress
                                    },
                            ),
                        )
                    update {
                        it.copy(configPreview = preview)
                            .appendLog("投影成功", LogLevel.Success, LogSource.Proxy)
                    }
                } catch (error: ProjectError) {
                    update {
                        it.copy(configPreview = error.contractCode)
                            .appendLog(
                                "投影失败：${error.contractCode}",
                                LogLevel.Error,
                                LogSource.Proxy,
                            )
                    }
                } catch (error: Exception) {
                    update {
                        it.copy(configPreview = error.message ?: "error")
                            .appendLog(
                                "投影失败：${error.message}",
                                LogLevel.Error,
                                LogSource.Proxy,
                            )
                    }
                }
            }

            fun applyNode(address: String, reconnect: Boolean) {
                val wasRunning = state.runtime.running
                val normalized = Ipv6Address.normalize(address)
                if (normalized == null || !Ipv6Address.isValid(normalized)) {
                    update {
                        it.appendLog(
                            "无效 IPv6：$address",
                            LogLevel.Error,
                            LogSource.Node,
                        )
                    }
                    return
                }
                update {
                    it.rememberCandidate(normalized)
                        .appendLog("已选择节点 $normalized", LogLevel.Success, LogSource.Node)
                }
                if (reconnect && wasRunning) {
                    startVpn(reason = "apply-node")
                }
            }

            fun applySpeedOutcome(result: CfstRunOutcome, installOk: Boolean, nodeTest: Boolean) {
                when (result) {
                    is CfstRunOutcome.Success -> {
                        update {
                            it.copy(
                                speedTest =
                                    it.speedTest.copy(
                                        isRunning = false,
                                        isNodeTest = false,
                                        message =
                                            if (nodeTest) {
                                                "当前节点测速完成：${result.results.size} 个结果"
                                            } else {
                                                result.message
                                            },
                                        results = result.results,
                                        binaryReady = true,
                                    ),
                            ).appendLog(
                                if (nodeTest) {
                                    "当前节点测速完成：${result.results.size} 个结果"
                                } else {
                                    result.message
                                },
                                LogLevel.Success,
                                LogSource.Node,
                            )
                        }
                    }
                    is CfstRunOutcome.Cancelled -> {
                        update {
                            it.copy(
                                speedTest =
                                    it.speedTest.copy(
                                        isRunning = false,
                                        isNodeTest = false,
                                        message = "测速已取消",
                                        binaryReady = installOk,
                                    ),
                            ).appendLog("测速已取消", LogLevel.Warning, LogSource.Node)
                        }
                    }
                    is CfstRunOutcome.Failed -> {
                        update {
                            it.copy(
                                speedTest =
                                    it.speedTest.copy(
                                        isRunning = false,
                                        isNodeTest = false,
                                        message = result.message,
                                        binaryReady = installOk,
                                    ),
                            ).appendLog(
                                "测速失败：${result.message}",
                                LogLevel.Error,
                                LogSource.Node,
                            )
                        }
                    }
                }
            }

            fun startSpeedTest() {
                if (state.speedTest.isRunning || cfstRunner.isRunning) {
                    update {
                        it.appendLog("测速已在进行中", LogLevel.Warning, LogSource.Node)
                    }
                    return
                }
                val useBundled = state.speedTest.useBundledList
                val ipRange = state.speedTest.ipRange
                val disableDownload = state.speedTest.disableDownload
                update {
                    it.copy(
                        speedTest =
                            it.speedTest.copy(
                                isRunning = true,
                                isNodeTest = false,
                                message = "正在准备 CFST…",
                            ),
                    ).appendLog("开始 IPv6 优选测速", LogLevel.Info, LogSource.Node)
                }
                scope.launch {
                    val outcome =
                        withContext(Dispatchers.IO) {
                            try {
                                val install = CfstInstaller.installIfNeeded(this@MainActivity)
                                val parameters =
                                    if (useBundled) {
                                        SpeedTestParameters(
                                            ipFile = install.ipv6List.absolutePath,
                                            disableDownload = disableDownload,
                                        )
                                    } else {
                                        SpeedTestParameters(
                                            ipRange = ipRange,
                                            disableDownload = disableDownload,
                                        )
                                    }
                                val work = CfstInstaller.workDir(this@MainActivity)
                                cfstRunner.run(install.binary, work, parameters) to true
                            } catch (error: Exception) {
                                CfstRunOutcome.Failed(error.message ?: "CFST 安装失败") to false
                            }
                        }
                    applySpeedOutcome(outcome.first, outcome.second, nodeTest = false)
                }
            }

            fun startCurrentNodeTest() {
                if (state.speedTest.isRunning || cfstRunner.isRunning) {
                    update {
                        it.appendLog("测速已在进行中", LogLevel.Warning, LogSource.Node)
                    }
                    return
                }
                val normalized = Ipv6Address.normalize(state.selectedAddress)
                if (normalized == null || !Ipv6Address.isValid(normalized)) {
                    update {
                        it.appendLog(
                            "当前节点测速需要合法 IPv6",
                            LogLevel.Error,
                            LogSource.Node,
                        )
                    }
                    return
                }
                val disableDownload = state.speedTest.disableDownload
                update {
                    it.copy(
                        speedTest =
                            it.speedTest.copy(
                                isRunning = true,
                                isNodeTest = true,
                                message = "正在对当前节点测速 $normalized…",
                            ),
                    ).appendLog(
                        "当前节点测速：$normalized",
                        LogLevel.Info,
                        LogSource.Node,
                    )
                }
                scope.launch {
                    val outcome =
                        withContext(Dispatchers.IO) {
                            try {
                                val install = CfstInstaller.installIfNeeded(this@MainActivity)
                                val parameters =
                                    SpeedTestParameters(
                                        ipRange = normalized,
                                        disableDownload = disableDownload,
                                        // Single-node config test: fewer threads is enough.
                                        threads = 50,
                                        downloadCount = 1,
                                    )
                                val work = CfstInstaller.workDir(this@MainActivity)
                                cfstRunner.run(install.binary, work, parameters) to true
                            } catch (error: Exception) {
                                CfstRunOutcome.Failed(error.message ?: "CFST 安装失败") to false
                            }
                        }
                    applySpeedOutcome(outcome.first, outcome.second, nodeTest = true)
                }
            }

            fun stopSpeedTest() {
                val cancelled = cfstRunner.requestCancel()
                if (cancelled) {
                    logOnly {
                        it.copy(
                            speedTest =
                                it.speedTest.copy(message = "正在停止测速…"),
                        ).appendLog("正在停止测速…", LogLevel.Info, LogSource.Node)
                    }
                }
            }

            fun refreshCfstStatus() {
                scope.launch {
                    val ready =
                        withContext(Dispatchers.IO) {
                            try {
                                val install = CfstInstaller.installIfNeeded(this@MainActivity)
                                install.binary.isFile && install.binary.length() > 0L
                            } catch (_: Exception) {
                                false
                            }
                        }
                    update {
                        it.copy(
                            speedTest =
                                it.speedTest.copy(
                                    binaryReady = ready,
                                    message =
                                        if (ready) {
                                            "CFST 已就绪（arm64）"
                                        } else {
                                            "未找到 CFST，请运行 node scripts/fetch-cfst.mjs"
                                        },
                                ),
                        ).appendLog(
                            if (ready) "CFST 组件就绪" else "CFST 组件缺失",
                            if (ready) LogLevel.Success else LogLevel.Warning,
                            LogSource.System,
                        )
                    }
                }
            }

            fun detectExitIp() {
                update {
                    it.copy(exitIP = it.exitIP.copy(isDetecting = true, errorMessage = null))
                        .appendLog("正在检测公网出口…", LogLevel.Info, LogSource.Network)
                }
                scope.launch {
                    val result =
                        withContext(Dispatchers.IO) {
                            ExitIPDetector.detect(
                                mode = state.exitIP.mode,
                                automaticEndpoint = state.exitIP.endpoint,
                            )
                        }
                    result.fold(
                        onSuccess = { info ->
                            update {
                                it.copy(
                                    exitIP =
                                        it.exitIP.copy(
                                            isDetecting = false,
                                            info = info,
                                            errorMessage = null,
                                        ),
                                ).appendLog(
                                    "出口 ${info.ip}" +
                                        (if (info.location.isNotBlank()) " · ${info.location}" else ""),
                                    LogLevel.Success,
                                    LogSource.Network,
                                )
                            }
                        },
                        onFailure = { error ->
                            update {
                                it.copy(
                                    exitIP =
                                        it.exitIP.copy(
                                            isDetecting = false,
                                            errorMessage = error.message,
                                        ),
                                ).appendLog(
                                    "出口检测失败：${error.message}",
                                    LogLevel.Error,
                                    LogSource.Network,
                                )
                            }
                        },
                    )
                }
            }

            fun runDelayTest() {
                if (!state.runtime.running) {
                    update {
                        it.appendLog("延迟测试需要先连接", LogLevel.Warning, LogSource.Proxy)
                    }
                    return
                }
                val name = state.profileSummary.primary?.name
                if (name.isNullOrBlank()) {
                    update {
                        it.appendLog("无法测试：缺少代理名称", LogLevel.Error, LogSource.Proxy)
                    }
                    return
                }
                update {
                    it.copy(delayTest = DelayTestState(isRunning = true))
                        .appendLog("测试代理延迟：$name", LogLevel.Info, LogSource.Proxy)
                }
                scope.launch {
                    val secret =
                        getSharedPreferences(ViaSixVpnService.RUNTIME_PREFS, MODE_PRIVATE)
                            .getString(ViaSixVpnService.KEY_SECRET, "")
                            .orEmpty()
                    val result =
                        withContext(Dispatchers.IO) {
                            ControllerClient.proxyDelay(
                                host = "127.0.0.1",
                                port = state.runtime.controllerPort,
                                secret = secret,
                                proxyName = name,
                            )
                        }
                    update {
                        it.copy(delayTest = DelayTestState(isRunning = false, last = result))
                            .appendLog(
                                if (result.ok) {
                                    "延迟 $name：${result.message}"
                                } else {
                                    "延迟测试失败：$name · ${result.message}"
                                },
                                if (result.ok) LogLevel.Success else LogLevel.Error,
                                LogSource.Proxy,
                            )
                    }
                }
            }

            fun patchRoutingMode(mode: RoutingMode) {
                val was = state.routingMode
                update { it.copy(routingMode = mode) }
                if (state.runtime.running && was != mode) {
                    scope.launch {
                        val secret =
                            getSharedPreferences(ViaSixVpnService.RUNTIME_PREFS, MODE_PRIVATE)
                                .getString(ViaSixVpnService.KEY_SECRET, "")
                                .orEmpty()
                        val ok =
                            withContext(Dispatchers.IO) {
                                ControllerClient.patchMode(
                                    "127.0.0.1",
                                    state.runtime.controllerPort,
                                    secret,
                                    mode.wire,
                                )
                            }
                        logOnly {
                            it.appendLog(
                                if (ok) {
                                    "已切换运行中模式 → ${mode.wire}"
                                } else {
                                    "运行中模式切换失败，下次连接生效：${mode.wire}"
                                },
                                if (ok) LogLevel.Success else LogLevel.Warning,
                                LogSource.Proxy,
                            )
                        }
                    }
                }
            }

            fun copyText(label: String, value: String) {
                val cm = getSystemService(ClipboardManager::class.java)
                cm.setPrimaryClip(ClipData.newPlainText(label, value))
                update {
                    it.appendLog("已复制 $label", LogLevel.Info, LogSource.Session)
                }
            }

            ViaSixApp(
                state = state,
                selectedSection = selectedSection,
                onSectionChange = { selectedSection = it },
                onProfileChange = { yaml -> update { it.copy(profileYaml = yaml) } },
                onImportProfile = {
                    openDocument.launch(arrayOf("text/*", "application/*", "*/*"))
                },
                onSelectedAddressChange = { ip -> update { it.copy(selectedAddress = ip) } },
                onApplyNode = { address, reconnect -> applyNode(address, reconnect) },
                onRemoveCandidate = { address ->
                    update {
                        it.copy(candidateAddresses = it.candidateAddresses.filter { c -> c != address })
                            .appendLog("已移除候选 $address", LogLevel.Info, LogSource.Node)
                    }
                },
                onSpeedIpRangeChange = { range ->
                    update { it.copy(speedTest = it.speedTest.copy(ipRange = range)) }
                },
                onSpeedUseBundledChange = { bundled ->
                    update { it.copy(speedTest = it.speedTest.copy(useBundledList = bundled)) }
                },
                onSpeedDisableDownloadChange = { disable ->
                    update { it.copy(speedTest = it.speedTest.copy(disableDownload = disable)) }
                },
                onStartSpeedTest = ::startSpeedTest,
                onStopSpeedTest = ::stopSpeedTest,
                onStartCurrentNodeTest = ::startCurrentNodeTest,
                onSpeedSortChange = { key ->
                    update {
                        val same = it.speedTest.sortKey == key
                        it.copy(
                            speedTest =
                                it.speedTest.copy(
                                    sortKey = key,
                                    sortAscending =
                                        if (same) !it.speedTest.sortAscending else true,
                                ),
                        )
                    }
                },
                onRefreshCfstStatus = ::refreshCfstStatus,
                onRoutingModeChange = ::patchRoutingMode,
                onFullTunnelChange = { full -> update { it.copy(fullTunnel = full) } },
                onStart = { startVpn("connect") },
                onStop = ::stopVpn,
                onProjectPreview = ::projectPreview,
                onDetectExitIp = ::detectExitIp,
                onExitIpModeChange = { mode ->
                    update { it.copy(exitIP = it.exitIP.copy(mode = mode)) }
                },
                onExitIpEndpointChange = { endpoint ->
                    update { it.copy(exitIP = it.exitIP.copy(endpoint = endpoint)) }
                },
                onDelayTest = ::runDelayTest,
                onCopy = ::copyText,
                onClearLogs = {
                    state = state.copy(logs = emptyList(), statusMessage = "日志已清空")
                },
                onDismissNotice = { state = state.copy(notice = null) },
                onClearSessionData = {
                    prefsStore.clear()
                    state = SessionUiState.fromPrefs(prefsStore.load())
                        .appendLog("已重置会话偏好", LogLevel.Warning, LogSource.System)
                },
            )
        }
    }
}
