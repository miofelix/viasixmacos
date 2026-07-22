package dev.viasix.app.state

import dev.viasix.app.mihomo.ProxyDelayResult
import dev.viasix.app.mihomo.TrafficSnapshot
import dev.viasix.app.net.ExitIPDetectionMode
import dev.viasix.app.net.ExitIPInfo
import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.core.net.Ipv6Address
import dev.viasix.core.profile.ProfileSummary
import dev.viasix.core.profile.ProfileSummaryParser
import dev.viasix.core.projection.RoutingMode
import dev.viasix.core.speedtest.SpeedTestParameters
import dev.viasix.core.speedtest.SpeedTestResult
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class LogLevel {
    Info,
    Success,
    Warning,
    Error,
}

enum class LogSource(val label: String) {
    Session("会话"),
    Proxy("代理"),
    Node("节点"),
    Network("网络"),
    System("系统"),
}

data class LogEntry(
    val id: Long,
    val timestamp: String,
    val message: String,
    val level: LogLevel = LogLevel.Info,
    val source: LogSource = LogSource.Session,
)

data class RuntimeSnapshot(
    val running: Boolean = false,
    val health: String = "—",
    val traffic: TrafficSnapshot = TrafficSnapshot.Idle,
    val controllerPort: Int = 9090,
    val mixedPort: Int = 11451,
    val mihomoVersion: String? = null,
    val secretPresent: Boolean = false,
    val startedAtMillis: Long? = null,
)

data class ExitIPState(
    val isDetecting: Boolean = false,
    val info: ExitIPInfo? = null,
    val errorMessage: String? = null,
    val mode: ExitIPDetectionMode = ExitIPDetectionMode.AUTOMATIC,
    val endpoint: String = "https://api.myip.la/cn?json",
)

data class DelayTestState(
    val isRunning: Boolean = false,
    val last: ProxyDelayResult? = null,
)

/**
 * CloudflareSpeedTest (IPv6 优选) session state.
 * Results feed the same apply-node / reconnect path as manual candidates.
 */
data class SpeedTestUiState(
    val isRunning: Boolean = false,
    val message: String = "需要先执行 node scripts/fetch-cfst.mjs 下载 CFST（arm64）",
    val results: List<SpeedTestResult> = emptyList(),
    val ipRange: String = SpeedTestParameters.DEFAULT_IPV6_RANGE,
    val useBundledList: Boolean = false,
    val disableDownload: Boolean = false,
    val binaryReady: Boolean = false,
)

/**
 * Full UI state for the Android shell. Session fields persist via [SessionPrefs];
 * runtime is polled from the VPN service + controller.
 */
data class SessionUiState(
    val profileYaml: String = "",
    val selectedAddress: String = "2001:db8::1",
    val candidateAddresses: List<String> = emptyList(),
    val routingMode: RoutingMode = RoutingMode.RULE,
    val fullTunnel: Boolean = true,
    val runtime: RuntimeSnapshot = RuntimeSnapshot(),
    val exitIP: ExitIPState = ExitIPState(),
    val delayTest: DelayTestState = DelayTestState(),
    val speedTest: SpeedTestUiState = SpeedTestUiState(),
    val statusMessage: String = "就绪",
    val statusLevel: LogLevel = LogLevel.Info,
    val logs: List<LogEntry> = emptyList(),
    val configPreview: String = "",
    val notice: AppNotice? = null,
) {
    val profileSummary: ProfileSummary
        get() = ProfileSummaryParser.parse(profileYaml)

    val selectedIsIpv6: Boolean
        get() = Ipv6Address.isValid(selectedAddress)

    val configurationReady: Boolean
        get() =
            routingMode == RoutingMode.DIRECT ||
                (profileYaml.isNotBlank() && selectedIsIpv6 && profileSummary.primary != null)

    fun toPrefs(): SessionPrefs =
        SessionPrefs(
            profileYaml = profileYaml,
            selectedAddress = selectedAddress,
            routingMode = routingMode.wire,
            fullTunnel = fullTunnel,
            candidateAddresses = candidateAddresses,
            exitIPEndpoint = exitIP.endpoint,
            exitIPDetectionMode = exitIP.mode.wire,
            lastSpeedIpRange = speedTest.ipRange,
            speedUseBundledList = speedTest.useBundledList,
            speedDisableDownload = speedTest.disableDownload,
        )

    companion object {
        val defaultProfile =
            """
            proxies:
              - name: My VLESS
                type: vless
                server: origin.example.com
                port: 443
                uuid: 11111111-1111-4111-1111-111111111111
            x-viasix:
              version: 1
              primary-server: selected-ip
            """.trimIndent()

        fun fromPrefs(prefs: SessionPrefs): SessionUiState {
            val selected = prefs.selectedAddress.ifBlank { "2001:db8::1" }
            val candidates =
                (listOf(selected) + prefs.candidateAddresses)
                    .mapNotNull { Ipv6Address.normalize(it) }
                    .distinct()
                    .take(50)
            return SessionUiState(
                profileYaml = prefs.profileYaml.ifBlank { defaultProfile },
                selectedAddress = selected,
                candidateAddresses = candidates,
                routingMode = RoutingMode.parse(prefs.routingMode) ?: RoutingMode.RULE,
                fullTunnel = prefs.fullTunnel,
                exitIP =
                    ExitIPState(
                        mode = ExitIPDetectionMode.parse(prefs.exitIPDetectionMode),
                        endpoint = prefs.exitIPEndpoint,
                    ),
                speedTest =
                    SpeedTestUiState(
                        ipRange = prefs.lastSpeedIpRange,
                        useBundledList = prefs.speedUseBundledList,
                        disableDownload = prefs.speedDisableDownload,
                    ),
            )
        }
    }
}

data class AppNotice(
    val id: Long,
    val message: String,
    val style: LogLevel,
    val actionOpenSettings: Boolean = false,
)

object LogClock {
    private val format = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    private var nextId = 1L

    fun now(): String = format.format(Date())

    fun nextId(): Long = nextId++
}

fun SessionUiState.appendLog(
    message: String,
    level: LogLevel = LogLevel.Info,
    source: LogSource = LogSource.Session,
    maxEntries: Int = 500,
    asNotice: Boolean = false,
): SessionUiState {
    val entry =
        LogEntry(
            id = LogClock.nextId(),
            timestamp = LogClock.now(),
            message = message,
            level = level,
            source = source,
        )
    return copy(
        statusMessage = message,
        statusLevel = level,
        logs = (listOf(entry) + logs).take(maxEntries),
        notice =
            if (asNotice) {
                AppNotice(
                    id = entry.id,
                    message = message,
                    style = level,
                    actionOpenSettings = level == LogLevel.Error,
                )
            } else {
                notice
            },
    )
}

fun SessionUiState.rememberCandidate(address: String): SessionUiState {
    val normalized = Ipv6Address.normalize(address) ?: return this
    val next =
        (listOf(normalized) + candidateAddresses.filter { it != normalized })
            .take(50)
    return copy(candidateAddresses = next, selectedAddress = normalized)
}
