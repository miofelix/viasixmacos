package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpWindowSurfaceTest {
    @Test
    fun advertisedWindowLimitsRemoteSocketReads() {
        val packet =
            resolve(
                "src/main/java/dev/viasix/app/tun/Packet.kt",
                "app/src/main/java/dev/viasix/app/tun/Packet.kt",
            ).readText()
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()
        val window =
            resolve(
                "src/main/java/dev/viasix/app/tun/TcpSendWindow.kt",
                "app/src/main/java/dev/viasix/app/tun/TcpSendWindow.kt",
            ).readText()

        assertTrue(packet.contains("val window: Int"))
        assertTrue(packet.contains("val windowScale: Int?"))
        assertTrue(packet.contains("start + 14"))
        assertTrue(engine.contains("session.sendWindow.update"))
        assertTrue(engine.contains("TcpWindowScale.expand"))
        assertTrue(engine.contains("clientWindowScale = tcp.windowScale"))
        assertTrue(engine.contains("windowScale ="))
        assertTrue(window.contains("maxInFlightBytes"))
        assertTrue(window.contains("TcpRetransmissionQueue.DEFAULT_MAX_RETAINED_BYTES"))
        assertTrue(engine.contains("session.sendWindow.awaitAllowance"))
        assertTrue(window.contains("System.nanoTime()"))
        assertFalse(window.contains("System.currentTimeMillis()"))
        assertTrue(engine.contains("session.sendWindow.recordSent"))
        assertTrue(engine.contains("input.read(buf, 0, allowance)"))
        assertTrue(engine.contains("sendWindow.cancel()"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
