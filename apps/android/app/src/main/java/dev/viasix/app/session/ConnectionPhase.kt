package dev.viasix.app.session

/**
 * Lightweight connection lifecycle for the Android shell.
 * Mirrors macOS [ProxyCorePhase] (stopped / starting / running / stopping)
 * without the full desktop state machine.
 */
enum class ConnectionPhase {
    STOPPED,
    STARTING,
    RUNNING,
    STOPPING,
    ;

    val isBusy: Boolean
        get() = this == STARTING || this == STOPPING

    val isActiveOrTransitioning: Boolean
        get() = this == STARTING || this == RUNNING || this == STOPPING

    /** Primary button label for Overview / hero control. */
    fun actionLabel(): String =
        when (this) {
            STOPPED -> "连接"
            STARTING -> "连接中…"
            RUNNING -> "断开"
            STOPPING -> "断开中…"
        }

    /** Header badge text. */
    fun statusLabel(): String =
        when (this) {
            STOPPED -> "未连接"
            STARTING -> "连接中"
            RUNNING -> "已连接"
            STOPPING -> "断开中"
        }

    companion object {
        /**
         * Reconcile local intent with polled VPN runtime.
         * [runtimeRunning] comes from [ViaSixVpnService] prefs.
         */
        fun reconcile(
            current: ConnectionPhase,
            runtimeRunning: Boolean,
        ): ConnectionPhase =
            when {
                runtimeRunning -> RUNNING
                current == STARTING -> STARTING // keep until timeout or running
                current == STOPPING -> STOPPED
                current == RUNNING -> STOPPED // unexpected drop
                else -> STOPPED
            }

        /**
         * After a long [STARTING] without runtime, treat as failed start.
         */
        fun afterStartTimeout(
            current: ConnectionPhase,
            runtimeRunning: Boolean,
        ): ConnectionPhase =
            when {
                runtimeRunning -> RUNNING
                current == STARTING -> STOPPED
                else -> current
            }
    }
}
