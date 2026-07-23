package dev.viasix.app.tun

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OutboundPacketQueueTest {
    @Test
    fun droppablePacketNeverEvictsLosslessTcpPacket() {
        val queue = OutboundPacketQueue(capacity = 1)
        val tcp = byteArrayOf(1)

        assertTrue(queue.offer(tcp, lossless = true))
        assertFalse(queue.offer(byteArrayOf(2), lossless = false))
        assertArrayEquals(tcp, queue.poll(timeoutMs = 0L))
    }

    @Test
    fun newestDatagramMayReplaceOlderDroppablePacket() {
        val queue = OutboundPacketQueue(capacity = 1)

        assertTrue(queue.offer(byteArrayOf(1), lossless = false))
        assertTrue(queue.offer(byteArrayOf(2), lossless = false))
        assertArrayEquals(byteArrayOf(2), queue.poll(timeoutMs = 0L))
        assertNull(queue.poll(timeoutMs = 0L))
    }

    @Test
    fun losslessPacketEvictsQueuedDatagramBeforeWaiting() {
        val queue = OutboundPacketQueue(capacity = 1)
        val tcp = byteArrayOf(2)

        assertTrue(queue.offer(byteArrayOf(1), lossless = false))
        assertTrue(queue.offer(tcp, lossless = true, timeoutMs = 0L))

        assertArrayEquals(tcp, queue.poll(timeoutMs = 0L))
        assertNull(queue.poll(timeoutMs = 0L))
    }

    @Test
    fun losslessPacketDoesNotEvictAnotherLosslessPacket() {
        val queue = OutboundPacketQueue(capacity = 1)
        val first = byteArrayOf(1)

        assertTrue(queue.offer(first, lossless = true))
        assertFalse(queue.offer(byteArrayOf(2), lossless = true, timeoutMs = 0L))

        assertArrayEquals(first, queue.poll(timeoutMs = 0L))
    }
}
