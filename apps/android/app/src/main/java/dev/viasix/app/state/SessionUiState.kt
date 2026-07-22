package dev.viasix.app.state

import dev.viasix.app.mihomo.TrafficSample
import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.core.projection.RoutingMode
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class LogEntry(
    val id: Long,
    val timestamp: String,
    val message: String,
    val level: LogLevel = LogLevel.Info,
)

enum class LogLevel {
    Info,
    Success,
    Error,
}

data class RuntimeSnapshot(
    val running: Boolean = false,
    val health: String = "—",
    val traffic: TrafficSample = TrafficSample(live = false, message = "—"),
    val controllerPort: Int = 9090,
    val mixedPort: Int = 11451,
    val mihomoVersion: String? = null,
)

/**
 * In-memory UI state for the Android shell. Session fields persist via
 * [SessionPrefs]; runtime is polled from the VPN service.
 */
data class SessionUiState(
    val profileYaml: String = "",
    val selectedAddress: String = "2001:db8::1",
    val routingMode: RoutingMode = RoutingMode.RULE,
    val fullTunnel: Boolean = true,
    val runtime: RuntimeSnapshot = RuntimeSnapshot(),
    val statusMessage: String = "就绪",
    val statusLevel: LogLevel = LogLevel.Info,
    val logs: List<LogEntry> = emptyList(),
    val configPreview: String = "",
) {
    fun toPrefs(): SessionPrefs =
        SessionPrefs(
            profileYaml = profileYaml,
            selectedAddress = selectedAddress,
            routingMode = routingMode.wire,
            fullTunnel = fullTunnel,
        )

    companion object {
        private val defaultProfile =
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

        fun fromPrefs(prefs: SessionPrefs): SessionUiState =
            SessionUiState(
                profileYaml = prefs.profileYaml.ifBlank { defaultProfile },
                selectedAddress = prefs.selectedAddress.ifBlank { "2001:db8::1" },
                routingMode = RoutingMode.parse(prefs.routingMode) ?: RoutingMode.RULE,
                fullTunnel = prefs.fullTunnel,
            )
    }
}

object LogClock {
    private val format = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    private var nextId = 1L

    fun now(): String = format.format(Date())

    fun nextId(): Long = nextId++
}

fun SessionUiState.appendLog(
    message: String,
    level: LogLevel = LogLevel.Info,
    maxEntries: Int = 200,
): SessionUiState {
    val entry =
        LogEntry(
            id = LogClock.nextId(),
            timestamp = LogClock.now(),
            message = message,
            level = level,
        )
    return copy(
        statusMessage = message,
        statusLevel = level,
        logs = (listOf(entry) + logs).take(maxEntries),
    )
}
