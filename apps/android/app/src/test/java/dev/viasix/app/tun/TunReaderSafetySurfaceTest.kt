package dev.viasix.app.tun

import org.junit.Assert.assertEquals
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
        assertTrue(packet.contains("totalLength > buffer.limit() - start"))
        assertTrue(packet.contains("dataOffset > l4Length"))
        assertTrue(packet.contains("length != l4Length"))
    }

    @Test
    fun startupAndWriterFailureCannotLeaveEngineReportedAsRunning() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(engine.contains("private var inChannel: FileChannel? = null"))
        assertTrue(engine.contains("private var outStream: FileOutputStream? = null"))
        assertTrue(engine.contains("tun write failed"))
        assertTrue(engine.contains("catch (error: Throwable) {\n            stop()\n            throw error"))
        assertTrue(engine.contains("inChannel?.close()"))
        assertTrue(engine.contains("outStream?.close()"))
        assertEquals(
            2,
            Regex("finally \\{\\s+running\\.set\\(false\\)").findAll(engine).count(),
        )
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
