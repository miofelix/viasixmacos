package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpUpstreamSurfaceTest {
    @Test
    fun clientPayloadsUseBoundedQueueAndDrainBeforeOutputShutdown() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()
        val queue =
            resolve(
                "src/main/java/dev/viasix/app/tun/TcpUpstreamQueue.kt",
                "app/src/main/java/dev/viasix/app/tun/TcpUpstreamQueue.kt",
            ).readText()

        assertTrue(engine.contains("session.upstream.offer(payload)"))
        assertTrue(engine.contains("ioWorkers.execute { writeTcpUpstream(key, session, socket) }"))
        assertTrue(engine.contains("session.upstreamWriterActive.compareAndSet(false, true)"))
        assertTrue(engine.contains("UPSTREAM_WRITER_IDLE_MS"))
        assertTrue(engine.contains("session.upstream.hasPending"))
        assertTrue(engine.contains("session.upstream.complete(payload.size)"))
        assertTrue(engine.contains("session.upstream.advertisedWindow()"))
        assertTrue(engine.contains("session.windowUpdatePending.set(true)"))
        assertTrue(engine.contains("session.windowUpdatePending.compareAndSet(true, false)"))
        assertTrue(engine.contains("!enqueueAck(session)"))
        assertTrue(engine.contains("socket.shutdownOutput()"))
        assertTrue(engine.contains("session.outputShutdown.compareAndSet(false, true)"))
        assertTrue(queue.contains("System.nanoTime()"))
        assertFalse(queue.contains("System.currentTimeMillis()"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
