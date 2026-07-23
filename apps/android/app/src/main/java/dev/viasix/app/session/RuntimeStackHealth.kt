package dev.viasix.app.session

enum class RuntimeStackFailure {
    MIHOMO_EXITED,
    TUNNEL_EXITED,
}

/** Pure health gate shared by the service supervisor and unit tests. */
object RuntimeStackHealth {
    fun failure(
        mihomoRunning: Boolean,
        fullTunnel: Boolean,
        tunnelRunning: Boolean,
    ): RuntimeStackFailure? =
        when {
            !mihomoRunning -> RuntimeStackFailure.MIHOMO_EXITED
            fullTunnel && !tunnelRunning -> RuntimeStackFailure.TUNNEL_EXITED
            else -> null
        }
}
