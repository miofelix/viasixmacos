package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpReceiveWindowSurfaceTest {
    @Test
    fun synchronizedSegmentsAreValidatedBeforeAcknowledgementAndPayload() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        val validation = engine.indexOf("!TcpReceiveWindow.accepts(")
        val acknowledgement = engine.indexOf("session.sendWindow.update(")
        val payload = engine.indexOf("TcpSequence.consumedPayloadPrefix(")
        assertTrue(validation >= 0)
        assertTrue(validation < acknowledgement)
        assertTrue(validation < payload)
        assertTrue(engine.contains("tcp.flags and Packet.ACK == 0"))
        assertTrue(engine.contains("nextExpected = session.clientNextSeq"))
        assertTrue(engine.contains("enqueueAck(session)\n            return"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
