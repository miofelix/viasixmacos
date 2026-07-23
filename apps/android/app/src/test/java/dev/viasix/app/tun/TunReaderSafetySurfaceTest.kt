package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TunReaderSafetySurfaceTest {
    @Test
    fun malformedFrameCannotLeaveReaderReportedAsRunning() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()
        val packet =
            resolve(
                "src/main/java/dev/viasix/app/tun/Packet.kt",
                "app/src/main/java/dev/viasix/app/tun/Packet.kt",
            ).readText()

        assertTrue(engine.contains("drop malformed TUN packet"))
        assertTrue(engine.contains("finally {\n                        running.set(false)"))
        assertTrue(packet.contains("totalLength > buffer.limit() - start"))
        assertTrue(packet.contains("dataOffset > l4Length"))
        assertTrue(packet.contains("length != l4Length"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
