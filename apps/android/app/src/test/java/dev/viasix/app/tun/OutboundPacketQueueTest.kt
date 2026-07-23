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
}
