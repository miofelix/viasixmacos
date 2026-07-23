package dev.viasix.app.tun

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpResetPolicySurfaceTest {
    @Test
    fun synchronizedResetUsesRfc5961SequenceValidation() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(engine.contains("TcpResetPolicy.classify("))
        assertTrue(engine.contains("if (session.socket == null) return"))
        assertTrue(engine.contains("nextExpected = session.clientNextSeq"))
        assertTrue(engine.contains("TcpResetPolicy.Action.CLOSE -> removeSession(key, session)"))
        assertTrue(engine.contains("TcpResetPolicy.Action.CHALLENGE_ACK"))
        assertTrue(engine.contains("enqueueChallengeAck(session)"))
        assertTrue(engine.contains("TcpResetPolicy.Action.DROP -> Unit"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
