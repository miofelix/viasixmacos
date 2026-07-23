package dev.viasix.app.tun

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

        assertTrue(engine.contains("session.upstream.offer(payload)"))
        assertTrue(engine.contains("ioWorkers.execute { writeTcpUpstream(key, session, socket) }"))
        assertTrue(engine.contains("session.upstreamWriterActive.compareAndSet(false, true)"))
        assertTrue(engine.contains("UPSTREAM_WRITER_IDLE_MS"))
        assertTrue(engine.contains("session.upstream.hasPending"))
        assertTrue(engine.contains("session.upstream.complete(payload.size)"))
        assertTrue(engine.contains("socket.shutdownOutput()"))
        assertTrue(engine.contains("session.outputShutdown.compareAndSet(false, true)"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
