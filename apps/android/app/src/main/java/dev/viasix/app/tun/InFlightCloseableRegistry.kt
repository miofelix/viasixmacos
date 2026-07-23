package dev.viasix.app.tun

import java.io.Closeable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Owns blocking I/O resources until they are published to their long-lived owner. */
internal class InFlightCloseableRegistry : AutoCloseable {
    private val closed = AtomicBoolean(false)
    private val closeables = ConcurrentHashMap.newKeySet<Closeable>()

    fun register(closeable: Closeable): Boolean {
        if (closed.get()) {
            closeQuietly(closeable)
            return false
        }
        closeables.add(closeable)
        if (!closed.get()) return true
        if (closeables.remove(closeable)) closeQuietly(closeable)
        return false
    }

    fun unregister(closeable: Closeable) {
        closeables.remove(closeable)
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        for (closeable in closeables.toList()) {
            if (closeables.remove(closeable)) closeQuietly(closeable)
        }
    }

    private fun closeQuietly(closeable: Closeable) {
        try {
            closeable.close()
        } catch (_: Exception) {
        }
    }
}
