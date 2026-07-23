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

    fun offer(
        packet: ByteArray,
        lossless: Boolean,
        timeoutMs: Long = 0L,
    ): Boolean {
        val entry = Entry(packet, lossless)
        if (lossless) {
            return try {
                queue.offer(entry, timeoutMs.coerceAtLeast(0L), TimeUnit.MILLISECONDS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                false
            }
        }

        if (queue.offer(entry)) return true
        val droppable = queue.firstOrNull { !it.lossless } ?: return false
        if (!queue.remove(droppable)) return false
        return queue.offer(entry)
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
}
