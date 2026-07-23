package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean

class InFlightCloseableRegistryTest {
    @Test
    fun closeClosesRegisteredResourcesAndRejectsLateRegistration() {
        val registry = InFlightCloseableRegistry()
        val active = TestCloseable()

        assertTrue(registry.register(active))
        registry.close()
        assertTrue(active.closed.get())

        val late = TestCloseable()
        assertFalse(registry.register(late))
        assertTrue(late.closed.get())
    }

    @Test
    fun unregisterTransfersOwnershipWithoutClosingResource() {
        val registry = InFlightCloseableRegistry()
        val transferred = TestCloseable()

        assertTrue(registry.register(transferred))
        registry.unregister(transferred)
        registry.close()

        assertFalse(transferred.closed.get())
        transferred.close()
    }

    private class TestCloseable : Closeable {
        val closed = AtomicBoolean(false)

        override fun close() {
            closed.set(true)
        }
    }
}
