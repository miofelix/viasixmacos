package dev.viasix.app.tun

/**
 * Owns at most one closeable relay and makes publication race safely with shutdown.
 *
 * A relay that finishes opening after its client was evicted is rejected and closed
 * immediately, so it cannot escape the relay table and leak sockets.
 */
internal class CloseableRelaySlot<T : AutoCloseable> : AutoCloseable {
    @Volatile
    private var closed = false

    @Volatile
    private var value: T? = null

    val isClosed: Boolean
        get() = closed

    fun current(): T? = value

    /** Transfers ownership of [candidate] to this slot, or closes it if no longer active. */
    fun publish(candidate: T): Boolean {
        val accepted =
            synchronized(this) {
                if (closed || value != null) {
                    false
                } else {
                    value = candidate
                    true
                }
            }
        if (!accepted) closeQuietly(candidate)
        return accepted
    }

    override fun close() {
        val active =
            synchronized(this) {
                if (closed) return
                closed = true
                value.also { value = null }
            }
        closeQuietly(active)
    }

    private fun closeQuietly(closeable: T?) {
        try {
            closeable?.close()
        } catch (_: Exception) {
        }
    }
}
