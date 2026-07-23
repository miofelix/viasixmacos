package dev.viasix.app.session

import android.content.Context
import android.content.Intent
import android.net.VpnService
import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.app.prefs.SessionPrefsStore
import dev.viasix.app.vpn.ViaSixVpnService
import dev.viasix.core.projection.RoutingMode

/**
 * Builds start/stop intents from persisted [SessionPrefs] so the Quick Settings tile
 * and the activity share one path (Clash / NekoBox-style system controls).
 */
object VpnSessionCommands {
    const val EXTRA_REQUEST_START = "dev.viasix.app.REQUEST_START_VPN"

    fun loadPrefs(context: Context): SessionPrefs = SessionPrefsStore(context).load()

    fun isRuntimeRunning(context: Context): Boolean {
        val prefs =
            context.getSharedPreferences(ViaSixVpnService.RUNTIME_PREFS, Context.MODE_PRIVATE)
        val owner = prefs.getString(ViaSixVpnService.KEY_PROCESS_TOKEN, "")
        return prefs.getBoolean(ViaSixVpnService.KEY_RUNNING, false) &&
            owner == RuntimeProcessIdentity.token
    }

    fun evaluateStart(prefs: SessionPrefs): SessionStartGate.Result {
        val mode = RoutingMode.parse(prefs.routingMode) ?: RoutingMode.RULE
        return SessionStartGate.evaluate(mode, prefs.selectedAddress, prefs.profileYaml)
    }

    fun buildStartIntent(
        context: Context,
        prefs: SessionPrefs,
        reason: String,
    ): Intent =
        Intent(context, ViaSixVpnService::class.java)
            .putExtra(ViaSixVpnService.EXTRA_PROFILE, prefs.profileYaml)
            .putExtra(ViaSixVpnService.EXTRA_SELECTED_IP, prefs.selectedAddress)
            .putExtra(ViaSixVpnService.EXTRA_MODE, prefs.routingMode)
            .putExtra(ViaSixVpnService.EXTRA_FULL_TUNNEL, prefs.fullTunnel)
            .putExtra(ViaSixVpnService.EXTRA_REASON, reason)

    fun buildStopIntent(context: Context): Intent =
        Intent(context, ViaSixVpnService::class.java).setAction(ViaSixVpnService.ACTION_STOP)

    /**
     * Starts the VPN service if consent already granted; otherwise returns a prepare Intent
     * the caller must launch (activity) or an error gate.
     */
    sealed class StartAction {
        data class StartService(val intent: Intent) : StartAction()

        data class NeedsVpnConsent(val prepare: Intent, val pendingStart: Intent) : StartAction()

        data class Blocked(val gate: SessionStartGate.Result.Blocked) : StartAction()
    }

    fun prepareStart(
        context: Context,
        prefs: SessionPrefs = loadPrefs(context),
        reason: String = "tile",
    ): StartAction {
        when (val gate = evaluateStart(prefs)) {
            is SessionStartGate.Result.Blocked -> return StartAction.Blocked(gate)
            SessionStartGate.Result.Ok -> Unit
        }
        val start = buildStartIntent(context, prefs, reason)
        val prepare = VpnService.prepare(context)
        return if (prepare != null) {
            StartAction.NeedsVpnConsent(prepare, start)
        } else {
            StartAction.StartService(start)
        }
    }
}
