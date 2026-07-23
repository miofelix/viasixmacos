package dev.viasix.app.tun

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpUpstreamQueueTest {
    @Test
    fun preservesOrderAndBoundsQueuedPayloads() {
        val queue = TcpUpstreamQueue(maxBytes = 4, maxSegments = 2)

        assertEquals(4, queue.advertisedWindow())
        assertTrue(queue.offer(byteArrayOf(1, 2)))
        assertEquals(2, queue.advertisedWindow())
        assertTrue(queue.offer(byteArrayOf(3, 4)))
        assertEquals(0, queue.advertisedWindow())
        assertTrue(queue.hasPending)
        assertFalse(queue.offer(byteArrayOf(5)))
        assertArrayEquals(byteArrayOf(1, 2), queue.poll(timeoutMs = 0L))
        assertFalse(queue.offer(byteArrayOf(5)))
        assertTrue(queue.complete(payloadLength = 2))
        assertEquals(2, queue.advertisedWindow())
        assertArrayEquals(byteArrayOf(3, 4), queue.poll(timeoutMs = 0L))
        assertFalse(queue.complete(payloadLength = 2))
        assertEquals(4, queue.advertisedWindow())
        assertTrue(queue.awaitEmpty(timeoutMs = 0L))
        assertFalse(queue.hasPending)
        assertNull(queue.poll(timeoutMs = 0L))
    }

    @Test
    fun cancelledQueueRejectsAndWakesConsumers() {
        val queue = TcpUpstreamQueue()

        queue.cancel()

        assertEquals(0, queue.advertisedWindow())
        assertFalse(queue.offer(byteArrayOf(1)))
        assertNull(queue.poll(timeoutMs = 0L))
        assertFalse(queue.awaitEmpty(timeoutMs = 0L))
    }

    @Test
    fun segmentLimitClosesWindowEvenWhenByteCapacityRemains() {
        val queue = TcpUpstreamQueue(maxBytes = 100, maxSegments = 1)

        assertTrue(queue.offer(byteArrayOf(1)))
        assertEquals(0, queue.advertisedWindow())
        assertArrayEquals(byteArrayOf(1), queue.poll(timeoutMs = 0L))
        assertTrue(queue.complete(payloadLength = 1))
        assertEquals(100, queue.advertisedWindow())
    }
}
