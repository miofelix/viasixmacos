package dev.viasix.app.tun

import org.junit.Assert.assertFalse
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
        assertTrue(engine.contains("socket.shutdownOutput()"))
        assertTrue(engine.contains("flags = Packet.FIN or Packet.ACK"))
        assertTrue(engine.contains("sessions[key] === session"))
        assertTrue(engine.contains("session.closeState.markClientFin()"))
        assertTrue(engine.contains("tcp.payloadLength > 0 && session.closeState.hasClientFin"))
        assertTrue(engine.contains("session.closeState.markServerFin"))
        assertTrue(engine.contains("session.closeState.acknowledgeServerFin"))
        assertTrue(engine.contains("session.retransmissions.reserve"))
        assertTrue(engine.contains("SERVER_HALF_CLOSE_TIMEOUT_MS"))
        assertTrue(engine.contains("var remoteEof = false"))
        assertTrue(engine.contains("tcp downstream read failed"))
        assertTrue(engine.contains("if (!remoteEof)"))
        assertTrue(engine.contains("rejectTcpSession(key, session)"))
        assertFalse(engine.contains("session.upstream.awaitEmpty"))
        assertFalse(engine.contains("UPSTREAM_DRAIN_TIMEOUT_MS"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
