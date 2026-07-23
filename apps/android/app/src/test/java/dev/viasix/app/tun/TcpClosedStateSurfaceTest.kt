package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpClosedStateSurfaceTest {
    @Test
    fun missingAndOverCapacitySessionsSendStatelessReset() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(engine.contains("session limit \$maxSessions reached; reset SYN"))
        assertTrue(engine.contains("tcp.flags and (Packet.ACK or Packet.RST or Packet.FIN) == 0"))
        assertEquals(
            2,
            Regex("enqueueClosedStateReset\\(tcp, clientIp, remoteIp, ipv6\\)").findAll(engine).count(),
        )
        assertTrue(engine.contains("TcpClosedStateReset.forSegment(tcp)"))
        assertTrue(engine.contains("return enqueuePacket(packet, lossless = true)"))
        assertFalse(engine.contains("sessions[key] ?: return"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
