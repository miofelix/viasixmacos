package dev.viasix.app.tun

import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** A bounded TUN writer queue where datagrams may yield, but TCP stream packets never do. */
class OutboundPacketQueue(capacity: Int) {
    private data class Entry(
        val packet: ByteArray,
        val lossless: Boolean,
    )

    private val queue = LinkedBlockingQueue<Entry>(capacity)
    private val offerLock = Any()

    fun offer(
        packet: ByteArray,
        lossless: Boolean,
        timeoutMs: Long = 0L,
    ): Boolean =
        synchronized(offerLock) {
            val entry = Entry(packet, lossless)
            if (queue.offer(entry)) return@synchronized true
            if (removeDroppable() && queue.offer(entry)) return@synchronized true
            if (lossless) {
                return@synchronized try {
                    queue.offer(entry, timeoutMs.coerceAtLeast(0L), TimeUnit.MILLISECONDS)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    false
                }
            }
            false
        }

    fun poll(timeoutMs: Long): ByteArray? =
        try {
            queue.poll(timeoutMs.coerceAtLeast(0L), TimeUnit.MILLISECONDS)?.packet
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            null
        }

    fun clear() {
        queue.clear()
    }

    private fun removeDroppable(): Boolean {
        val droppable = queue.firstOrNull { !it.lossless } ?: return false
        return queue.remove(droppable)
    }
}
