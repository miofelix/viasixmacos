package dev.viasix.app.session

import android.content.Context
import dev.viasix.app.mihomo.TrafficSnapshot
import dev.viasix.app.state.RuntimeSnapshot
import dev.viasix.app.vpn.ViaSixVpnService

/** Last runtime state published by [ViaSixVpnService], available across UI process recreation. */
data class SessionRuntimeStatus(
    val running: Boolean = false,
    val phase: ConnectionPhase = if (running) ConnectionPhase.RUNNING else ConnectionPhase.STOPPED,
    val health: String = "—",
    val controllerPort: Int = ViaSixVpnService.CONTROLLER_PORT,
    val mixedPort: Int = ViaSixVpnService.MIXED_PORT,
    val secret: String = "",
    val mihomoVersion: String? = null,
    val startedAtMillis: Long? = null,
    val eventsJson: String = "[]",
    val processToken: String = "",
    val underlyingNetwork: String = "正在检测",
) {
    /** A persisted active/transitioning phase is valid only while owned by this app process. */
    fun forProcess(currentProcessToken: String): SessionRuntimeStatus =
        if (!phase.isActiveOrTransitioning || processToken == currentProcessToken) {
            this
        } else {
            copy(
                running = false,
                phase = ConnectionPhase.STOPPED,
                health = "stopped",
                secret = "",
                mihomoVersion = null,
                startedAtMillis = null,
                processToken = "",
            )
        }

    fun toUiSnapshot(traffic: TrafficSnapshot = TrafficSnapshot.Idle): RuntimeSnapshot =
        RuntimeSnapshot(
            running = running,
            health = health,
            traffic = traffic,
            controllerPort = controllerPort,
            mixedPort = mixedPort,
            mihomoVersion = mihomoVersion,
            secretPresent = secret.isNotBlank(),
            startedAtMillis = startedAtMillis,
            underlyingNetwork = underlyingNetwork,
        )
}

class SessionRuntimeStore(context: Context) {
    private val prefs =
        context.getSharedPreferences(ViaSixVpnService.RUNTIME_PREFS, Context.MODE_PRIVATE)

    fun load(): SessionRuntimeStatus {
        val legacyRunning = prefs.getBoolean(ViaSixVpnService.KEY_RUNNING, false)
        val phase =
            ConnectionPhase.parse(prefs.getString(ViaSixVpnService.KEY_PHASE, null))
                ?: if (legacyRunning) ConnectionPhase.RUNNING else ConnectionPhase.STOPPED
        return SessionRuntimeStatus(
            running = phase == ConnectionPhase.RUNNING,
            phase = phase,
            health = prefs.getString(ViaSixVpnService.KEY_HEALTH, "—") ?: "—",
            controllerPort =
                prefs.getInt(
                    ViaSixVpnService.KEY_CONTROLLER_PORT,
                    ViaSixVpnService.CONTROLLER_PORT,
                ),
            mixedPort =
                prefs.getInt(
                    ViaSixVpnService.KEY_MIXED_PORT,
                    ViaSixVpnService.MIXED_PORT,
                ),
            secret = prefs.getString(ViaSixVpnService.KEY_SECRET, "") ?: "",
            mihomoVersion =
                prefs.getString(ViaSixVpnService.KEY_VERSION, "")
                    ?.ifBlank { null },
            startedAtMillis =
                prefs.getLong(ViaSixVpnService.KEY_STARTED_AT, 0L)
                    .takeIf { it > 0L },
            eventsJson = prefs.getString(ViaSixVpnService.KEY_EVENTS, "[]") ?: "[]",
            processToken = prefs.getString(ViaSixVpnService.KEY_PROCESS_TOKEN, "") ?: "",
            underlyingNetwork =
                prefs.getString(ViaSixVpnService.KEY_UNDERLYING_NETWORK, "正在检测")
                    ?: "正在检测",
        ).forProcess(RuntimeProcessIdentity.token)
    }
}
