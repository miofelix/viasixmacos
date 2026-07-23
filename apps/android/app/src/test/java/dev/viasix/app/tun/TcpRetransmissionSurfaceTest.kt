package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpRetransmissionSurfaceTest {
    @Test
    fun engineRetainsAcknowledgesAndRetransmitsTcpData() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(engine.contains("session.retransmissions.reserve"))
        assertTrue(engine.contains("session.retransmissions.markQueued"))
        assertTrue(engine.contains("session.retransmissions.acknowledge"))
        assertTrue(engine.contains("session.retransmissions.pollDue"))
        assertTrue(engine.contains("session.retransmissions.awaitEmpty"))
        assertTrue(engine.contains("Executors.newSingleThreadScheduledExecutor"))
        assertTrue(engine.contains("timeoutMs = 0L"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
