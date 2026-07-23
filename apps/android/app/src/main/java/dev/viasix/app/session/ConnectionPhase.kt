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

    val wire: String
        get() = name.lowercase()

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
        /** Restore the visible phase before the first runtime poll after UI recreation. */
        fun restore(
            runtimePhase: ConnectionPhase,
            hasPendingStart: Boolean = false,
        ): ConnectionPhase =
            when {
                runtimePhase != STOPPED -> runtimePhase
                hasPendingStart -> STARTING
                else -> STOPPED
            }

        /**
         * Reconcile local intent with polled VPN runtime.
         * [runtimePhase] comes from [ViaSixVpnService] prefs.
         */
        fun reconcile(
            current: ConnectionPhase,
            runtimePhase: ConnectionPhase,
        ): ConnectionPhase =
            when (runtimePhase) {
                RUNNING -> RUNNING
                STARTING -> STARTING
                STOPPING -> STOPPING
                STOPPED ->
                    when (current) {
                        STARTING -> STARTING // keep pending local consent until timeout
                        STOPPING, RUNNING, STOPPED -> STOPPED
                    }
            }

        /**
         * After a long UI [STARTING] without reaching [RUNNING], treat as failed start.
         *
         * Covers both “service never left STOPPED” (permission / never launched) and
         * “service stuck in STARTING” (worker hung after publishing STARTING). A late
         * [RUNNING] publication still wins.
         */
        fun afterStartTimeout(
            current: ConnectionPhase,
            runtimePhase: ConnectionPhase,
        ): ConnectionPhase =
            when {
                runtimePhase == RUNNING -> RUNNING
                current == STARTING -> STOPPED
                else -> current
            }

        /**
         * Whether the Activity poll loop should apply [afterStartTimeout].
         * [startingSinceMillis] is wall-clock when the UI entered STARTING for a
         * real start attempt (0 means no timed attempt).
         */
        fun shouldApplyStartTimeout(
            uiPhase: ConnectionPhase,
            runtimePhase: ConnectionPhase,
            runtimeRunning: Boolean,
            startingSinceMillis: Long,
            nowMillis: Long,
            timeoutMs: Long,
        ): Boolean {
            if (uiPhase != STARTING || runtimeRunning || startingSinceMillis <= 0L) {
                return false
            }
            if (runtimePhase == RUNNING) {
                return false
            }
            return nowMillis - startingSinceMillis > timeoutMs
        }

        fun parse(value: String?): ConnectionPhase? =
            entries.firstOrNull { it.wire.equals(value, ignoreCase = true) }
    }
}
