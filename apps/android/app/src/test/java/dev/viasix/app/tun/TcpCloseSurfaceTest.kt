package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpCloseSurfaceTest {
    @Test
    fun clientHalfCloseAndRemoteEofProduceTcpCloseSignals() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(engine.contains("TcpSequence.consumedPayloadPrefix"))
        assertTrue(engine.contains("session.socket?.shutdownOutput()"))
        assertTrue(engine.contains("flags = Packet.FIN or Packet.ACK"))
        assertTrue(engine.contains("sessions[key] === session"))
        assertTrue(engine.contains("clientFinReceived"))
        assertTrue(engine.contains("serverFinSent"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
