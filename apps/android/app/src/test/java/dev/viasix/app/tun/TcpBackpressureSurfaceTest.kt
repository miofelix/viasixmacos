package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpBackpressureSurfaceTest {
    @Test
    fun tcpControlAndPayloadPacketsUseLosslessBoundedQueue() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(engine.contains("OutboundPacketQueue(capacity = 512)"))
        assertTrue(engine.contains("LOSSLESS_ENQUEUE_TIMEOUT_MS"))
        assertTrue(engine.contains("val synAckQueued"))
        assertTrue(engine.contains("session.retransmissions.cancel()"))
        assertTrue(engine.contains("flags = Packet.FIN or Packet.ACK"))
        assertTrue(engine.contains("lossless = true"))
        assertTrue(engine.contains("timeoutMs: Long = if (lossless) LOSSLESS_ENQUEUE_TIMEOUT_MS else 0L"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
