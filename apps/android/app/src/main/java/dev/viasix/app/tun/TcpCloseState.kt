package dev.viasix.app.tun

class TcpCloseState {
    private val monitor = Object()
    private var clientFinReceived = false
    private var serverFinEnd: Long? = null
    private var serverFinSentAtMs = 0L
    private var serverFinAcknowledged = false

    val hasClientFin: Boolean
        get() = synchronized(monitor) { clientFinReceived }

    val isFullyClosed: Boolean
        get() = synchronized(monitor) { clientFinReceived && serverFinAcknowledged }

    fun markClientFin(): Boolean =
        synchronized(monitor) {
            if (clientFinReceived) return@synchronized false
            clientFinReceived = true
            true
        }

    fun markServerFin(
        sequenceEnd: Long,
        nowMs: Long,
    ): Boolean =
        synchronized(monitor) {
            if (serverFinEnd != null) return@synchronized false
            serverFinEnd = sequenceEnd
            serverFinSentAtMs = nowMs
            true
        }

    fun acknowledgeServerFin(acknowledgement: Long): Boolean =
        synchronized(monitor) {
            if (acknowledgement != serverFinEnd) return@synchronized false
            serverFinAcknowledged = true
            true
        }

    fun isExpired(
        nowMs: Long,
        timeoutMs: Long,
    ): Boolean =
        synchronized(monitor) {
            serverFinEnd != null &&
                nowMs - serverFinSentAtMs >= timeoutMs.coerceAtLeast(0L)
        }
}
