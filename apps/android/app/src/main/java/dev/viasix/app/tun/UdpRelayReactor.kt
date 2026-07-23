package dev.viasix.app.tun

import java.net.InetAddress
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

/** Multiplexes all non-blocking SOCKS5 UDP relay sockets on one daemon thread. */
internal class UdpRelayReactor(
    private val threadName: String = "viasix-udp-relay-reactor",
    private val controlProbeIntervalMs: Long = CONTROL_PROBE_INTERVAL_MS,
    private val maxQueuedDatagrams: Int = MAX_QUEUED_DATAGRAMS,
    private val maxQueuedBytes: Int = MAX_QUEUED_BYTES,
    private val onFatal: (Throwable) -> Unit = {},
    selectorFactory: () -> Selector = { Selector.open() },
) : AutoCloseable {
    init {
        require(controlProbeIntervalMs > 0L) { "controlProbeIntervalMs must be positive" }
        require(maxQueuedDatagrams > 0) { "maxQueuedDatagrams must be positive" }
        require(maxQueuedBytes > 0) { "maxQueuedBytes must be positive" }
    }

    enum class SendResult {
        QUEUED,
        QUEUE_FULL,
        UNAVAILABLE,
    }

    private class Registration(
        val relay: Socks5UdpRelay,
        val onDatagram: (Socks5UdpFraming.Datagram) -> Unit,
        val onClosed: () -> Unit,
        private val maxQueuedDatagrams: Int,
        private val maxQueuedBytes: Int,
    ) {
        val closedNotified = AtomicBoolean(false)
        val writeScheduled = AtomicBoolean(false)
        @Volatile var key: SelectionKey? = null
        private val active = AtomicBoolean(true)
        private val outbound = ArrayDeque<ByteArray>()
        private var outboundBytes = 0

        val isActive: Boolean
            get() = active.get()

        fun offer(frame: ByteArray): Boolean =
            synchronized(outbound) {
                if (
                    !active.get() ||
                    outbound.size >= maxQueuedDatagrams ||
                    outboundBytes + frame.size > maxQueuedBytes
                ) {
                    return@synchronized false
                }
                outbound.addLast(frame)
                outboundBytes += frame.size
                true
            }

        fun peek(): ByteArray? = synchronized(outbound) { outbound.firstOrNull() }

        fun remove(frame: ByteArray): Boolean =
            synchronized(outbound) {
                if (outbound.firstOrNull() !== frame) return@synchronized false
                outbound.removeFirst()
                outboundBytes -= frame.size
                true
            }

        fun hasOutbound(): Boolean = synchronized(outbound) { outbound.isNotEmpty() }

        fun deactivate() {
            if (!active.compareAndSet(true, false)) return
            synchronized(outbound) {
                outbound.clear()
                outboundBytes = 0
            }
        }
    }

    private val pending = ConcurrentLinkedQueue<Registration>()
    private val pendingWrites = ConcurrentLinkedQueue<Registration>()
    private val registrations = ConcurrentHashMap<Socks5UdpRelay, Registration>()
    private val selector = selectorFactory()
    private val running = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val lifecycleLock = Any()
    private var reactorThread: Thread? = null

    internal val registrationCount: Int
        get() = registrations.size

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
            val registration =
                Registration(
                    relay = relay,
                    onDatagram = onDatagram,
                    onClosed = onClosed,
                    maxQueuedDatagrams = maxQueuedDatagrams,
                    maxQueuedBytes = maxQueuedBytes,
                )
            if (registrations.putIfAbsent(relay, registration) != null) return false
            pending.add(registration)
            selector.wakeup()
            return true
        }
    }

    fun send(
        relay: Socks5UdpRelay,
        remote: InetAddress,
        remotePort: Int,
        payload: ByteArray,
    ): SendResult {
        if (closed.get() || !running.get() || !relay.isOpen) return SendResult.UNAVAILABLE
        val registration = registrations[relay] ?: return SendResult.UNAVAILABLE
        val frame = Socks5UdpFraming.wrap(remote, remotePort, payload)
        if (!registration.offer(frame)) {
            return if (registration.isActive) SendResult.QUEUE_FULL else SendResult.UNAVAILABLE
        }
        scheduleWrite(registration)
        return SendResult.QUEUED
    }

    fun unregister(relay: Socks5UdpRelay): Boolean {
        val registration = registrations[relay]
        if (registration != null) {
            registration.closedNotified.set(true)
            try {
                registration.key?.cancel()
            } catch (_: Exception) {
            }
            retire(registration)
        }
        relay.close()
        try {
            selector.wakeup()
        } catch (_: Exception) {
        }
        return registration != null
    }

    private fun runLoop() {
        var nextControlProbeMs = monotonicTimeMs() + controlProbeIntervalMs
        var fatalError: Exception? = null
        try {
            while (running.get()) {
                registerPending()
                flushScheduledWrites()
                val selectTimeoutMs =
                    (nextControlProbeMs - monotonicTimeMs()).coerceIn(1L, SELECT_TIMEOUT_MS)
                selector.select(selectTimeoutMs)
                val selected = selector.selectedKeys().iterator()
                while (selected.hasNext()) {
                    val key = selected.next()
                    selected.remove()
                    val registration = key.attachment() as? Registration ?: continue
                    if (!key.isValid) {
                        fail(key, registration)
                        continue
                    }
                    try {
                        if (key.isReadable) receiveDatagrams(registration)
                        if (key.isValid && key.isWritable) flushWrites(key, registration)
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
        } catch (error: Exception) {
            if (!closed.get()) fatalError = error
        } finally {
            running.set(false)
            closeAllRegistrations()
            try {
                selector.close()
            } catch (_: Exception) {
            }
        }
        fatalError?.let(::notifyFatal)
    }

    private fun notifyFatal(error: Throwable) {
        try {
            onFatal(error)
        } catch (_: Exception) {
        }
    }

    private fun registerPending() {
        while (true) {
            val registration = pending.poll() ?: return
            try {
                if (!registration.relay.isOpen) {
                    retire(registration)
                    registration.relay.close()
                    notifyClosed(registration)
                    continue
                }
                val key =
                    registration.relay.selectableChannel.register(
                        selector,
                        SelectionKey.OP_READ,
                        registration,
                    )
                registration.key = key
            } catch (_: Exception) {
                retire(registration)
                registration.relay.close()
                notifyClosed(registration)
            }
        }
    }

    private fun receiveDatagrams(registration: Registration) {
        var drained = 0
        while (drained < MAX_DATAGRAMS_PER_TURN) {
            val datagram = registration.relay.receiveNow() ?: break
            registration.onDatagram(datagram)
            drained += 1
        }
    }

    private fun scheduleWrite(registration: Registration) {
        if (!registration.isActive) return
        if (!registration.writeScheduled.compareAndSet(false, true)) return
        pendingWrites.add(registration)
        selector.wakeup()
    }

    private fun flushScheduledWrites() {
        while (true) {
            val registration = pendingWrites.poll() ?: return
            registration.writeScheduled.set(false)
            if (!registration.isActive) continue
            val key = registration.key
            if (key == null) {
                scheduleWrite(registration)
                return
            }
            if (!key.isValid) {
                fail(key, registration)
                continue
            }
            try {
                flushWrites(key, registration)
            } catch (_: Exception) {
                fail(key, registration)
            }
        }
    }

    private fun flushWrites(key: SelectionKey, registration: Registration) {
        var drained = 0
        while (drained < MAX_DATAGRAMS_PER_TURN) {
            val frame = registration.peek() ?: break
            if (!registration.relay.sendNow(frame)) {
                setWriteInterest(key, enabled = true)
                return
            }
            if (!registration.remove(frame)) return
            drained += 1
        }
        setWriteInterest(key, enabled = registration.hasOutbound())
    }

    private fun setWriteInterest(key: SelectionKey, enabled: Boolean) {
        if (!key.isValid) return
        val current = key.interestOps()
        val updated =
            if (enabled) {
                current or SelectionKey.OP_WRITE
            } else {
                current and SelectionKey.OP_WRITE.inv()
            }
        if (updated != current) key.interestOps(updated)
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
        retire(registration)
        registration.relay.close()
        notifyClosed(registration)
    }

    private fun retire(registration: Registration) {
        registrations.remove(registration.relay, registration)
        registration.key = null
        registration.deactivate()
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
            retire(registration)
            registration.relay.close()
            notifyClosed(registration)
        }
        for (registration in registrations.values.toList()) {
            retire(registration)
            registration.relay.close()
            notifyClosed(registration)
        }
        pendingWrites.clear()
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
        const val MAX_QUEUED_DATAGRAMS = 64
        const val MAX_QUEUED_BYTES = 512 * 1024
        const val CLOSE_JOIN_TIMEOUT_MS = 2_000L

        fun monotonicTimeMs(): Long = System.nanoTime() / 1_000_000L
    }
}
