package dev.viasix.app.session

class VpnStartupCancelledException(stage: String) :
    IllegalStateException("VPN startup cancelled at $stage")

object VpnStartupGate {
    fun requireActive(
        shuttingDown: Boolean,
        stage: String,
    ) {
        if (shuttingDown) throw VpnStartupCancelledException(stage)
    }
}
