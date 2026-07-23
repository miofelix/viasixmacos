package dev.viasix.app.tun

import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

/** Multiplexes all non-blocking SOCKS5 UDP relay sockets on one daemon thread. */
internal class UdpRelayReactor(
    private val threadName: String = "viasix-udp-relay-reactor",
    private val controlProbeIntervalMs: Long = CONTROL_PROBE_INTERVAL_MS,
) : AutoCloseable {
    init {
        require(controlProbeIntervalMs > 0L) { "controlProbeIntervalMs must be positive" }
    }

    private class Registration(
        val relay: Socks5UdpRelay,
        val onDatagram: (Socks5UdpFraming.Datagram) -> Unit,
        val onClosed: () -> Unit,
    ) {
        val closedNotified = AtomicBoolean(false)
    }

    private val selector = Selector.open()
    private val pending = ConcurrentLinkedQueue<Registration>()
    private val running = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val lifecycleLock = Any()
    private var reactorThread: Thread? = null

    fun start() {
        synchronized(lifecycleLock) {
            if (closed.get()) return
            if (!running.compareAndSet(false, true)) return
            reactorThread =
                Thread(::runLoop, threadName).apply {
                    isDaemon = true
                    start()
                }
        }
    }

    fun register(
        relay: Socks5UdpRelay,
        onDatagram: (Socks5UdpFraming.Datagram) -> Unit,
        onClosed: () -> Unit,
    ): Boolean {
        synchronized(lifecycleLock) {
            if (closed.get() || !running.get() || !relay.isOpen) return false
            pending.add(Registration(relay, onDatagram, onClosed))
            selector.wakeup()
            return true
        }
    }

    private fun runLoop() {
        var nextControlProbeMs = monotonicTimeMs() + controlProbeIntervalMs
        try {
            while (running.get()) {
                registerPending()
                val selectTimeoutMs =
                    (nextControlProbeMs - monotonicTimeMs()).coerceIn(1L, SELECT_TIMEOUT_MS)
                selector.select(selectTimeoutMs)
                val selected = selector.selectedKeys().iterator()
                while (selected.hasNext()) {
                    val key = selected.next()
                    selected.remove()
                    val registration = key.attachment() as? Registration ?: continue
                    if (!key.isValid || !key.isReadable) continue
                    try {
                        var drained = 0
                        while (drained < MAX_DATAGRAMS_PER_TURN) {
                            val datagram = registration.relay.receiveNow() ?: break
                            registration.onDatagram(datagram)
                            drained += 1
                        }
                    } catch (_: Exception) {
                        fail(key, registration)
                    }
                }

                val nowMs = monotonicTimeMs()
                if (nowMs >= nextControlProbeMs) {
                    probeControls()
                    nextControlProbeMs = nowMs + controlProbeIntervalMs
                }
            }
        } finally {
            running.set(false)
            closeAllRegistrations()
            try {
                selector.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun registerPending() {
        while (true) {
            val registration = pending.poll() ?: return
            try {
                if (!registration.relay.isOpen) {
                    notifyClosed(registration)
                    continue
                }
                registration.relay.selectableChannel.register(
                    selector,
                    SelectionKey.OP_READ,
                    registration,
                )
            } catch (_: Exception) {
                registration.relay.close()
                notifyClosed(registration)
            }
        }
    }

    private fun probeControls() {
        val keys =
            try {
                selector.keys().toList()
            } catch (_: Exception) {
                return
            }
        for (key in keys) {
            val registration = key.attachment() as? Registration ?: continue
            if (!key.isValid || !registration.relay.probeControlConnection()) {
                fail(key, registration)
            }
        }
    }

    private fun fail(key: SelectionKey, registration: Registration) {
        try {
            key.cancel()
        } catch (_: Exception) {
        }
        registration.relay.close()
        notifyClosed(registration)
    }

    private fun notifyClosed(registration: Registration) {
        if (!registration.closedNotified.compareAndSet(false, true)) return
        try {
            registration.onClosed()
        } catch (_: Exception) {
        }
    }

    private fun closeAllRegistrations() {
        val keys =
            try {
                selector.keys().toList()
            } catch (_: Exception) {
                emptyList()
            }
        for (key in keys) {
            val registration = key.attachment() as? Registration ?: continue
            fail(key, registration)
        }
        while (true) {
            val registration = pending.poll() ?: break
            registration.relay.close()
            notifyClosed(registration)
        }
    }

    override fun close() {
        val thread =
            synchronized(lifecycleLock) {
                if (!closed.compareAndSet(false, true)) return
                running.set(false)
                selector.wakeup()
                reactorThread
            }
        if (thread !== Thread.currentThread()) {
            try {
                thread?.join(CLOSE_JOIN_TIMEOUT_MS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        synchronized(lifecycleLock) {
            if (reactorThread === thread) reactorThread = null
        }
        if (thread == null) {
            closeAllRegistrations()
            try {
                selector.close()
            } catch (_: Exception) {
            }
        }
    }

    private companion object {
        const val SELECT_TIMEOUT_MS = 200L
        const val CONTROL_PROBE_INTERVAL_MS = 5_000L
        const val MAX_DATAGRAMS_PER_TURN = 32
        const val CLOSE_JOIN_TIMEOUT_MS = 2_000L

        fun monotonicTimeMs(): Long = System.nanoTime() / 1_000_000L
    }
}
