package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class CloseableRelaySlotTest {
    @Test
    fun closeBeforePublishRejectsAndClosesLateRelay() {
        val slot = CloseableRelaySlot<CountingCloseable>()
        val relay = CountingCloseable()

        slot.close()

        assertFalse(slot.publish(relay))
        assertNull(slot.current())
        assertEquals(1, relay.closeCount.get())
    }

    @Test
    fun publishedRelayIsClosedExactlyOnce() {
        val slot = CloseableRelaySlot<CountingCloseable>()
        val relay = CountingCloseable()

        assertTrue(slot.publish(relay))
        assertEquals(relay, slot.current())
        slot.close()
        slot.close()

        assertNull(slot.current())
        assertEquals(1, relay.closeCount.get())
    }

    @Test
    fun concurrentPublishAndCloseNeverLeaksRelay() {
        repeat(100) {
            val slot = CloseableRelaySlot<CountingCloseable>()
            val relay = CountingCloseable()
            val ready = CountDownLatch(2)
            val start = CountDownLatch(1)
            val pool = Executors.newFixedThreadPool(2)
            try {
                val publish =
                    pool.submit {
                        ready.countDown()
                        start.await()
                        slot.publish(relay)
                    }
                val close =
                    pool.submit {
                        ready.countDown()
                        start.await()
                        slot.close()
                    }
                assertTrue(ready.await(1, TimeUnit.SECONDS))
                start.countDown()
                publish.get(1, TimeUnit.SECONDS)
                close.get(1, TimeUnit.SECONDS)
                slot.close()
                assertEquals(1, relay.closeCount.get())
            } finally {
                pool.shutdownNow()
            }
        }
    }

    private class CountingCloseable : AutoCloseable {
        val closeCount = AtomicInteger(0)

        override fun close() {
            closeCount.incrementAndGet()
        }
    }
}
