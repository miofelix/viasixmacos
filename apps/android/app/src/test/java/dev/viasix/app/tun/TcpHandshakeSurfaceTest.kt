package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class TcpHandshakeSurfaceTest {
    @Test
    fun clientAckDrivesHandshakeAndDuplicateSynResendsStableSynAck() {
        val engine =
            resolve(
                "src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
                "app/src/main/java/dev/viasix/app/tun/Tun2SocksEngine.kt",
            ).readText()

        assertTrue(engine.contains("existing.handshake.isComplete"))
        assertTrue(engine.contains("enqueueSynAck(existing)"))
        assertTrue(engine.contains("enqueueChallengeAck(existing)"))
        assertTrue(engine.contains("if (tcp.flags and Packet.SYN != 0)"))
        assertTrue(engine.contains("enqueueChallengeAck(session)"))
        assertTrue(engine.contains("session.challengeAcks.tryAcquire(monotonicTimeMs())"))
        assertTrue(engine.contains("session.handshake.acknowledge"))
        assertTrue(engine.contains("expectedSequence = session.clientNextSeq"))
        assertTrue(engine.contains("expectedAcknowledgement = session.serverSeq"))
        assertTrue(engine.contains("flags = tcp.flags"))
        assertTrue(engine.contains("session.socket != null"))
        val openSession =
            engine.substring(
                engine.indexOf("private fun openTcpSession"),
                engine.indexOf("private fun ensureTcpDownstreamReader"),
            )
        val retainedSyn =
            engine.substring(
                engine.indexOf("private fun retainAndEnqueueSynAck"),
                engine.indexOf("private fun ensureTcpUpstreamWriter"),
            )
        val retransmission =
            engine.substring(
                engine.indexOf("private fun enqueueTcpRetransmission"),
                engine.indexOf("private fun enqueueAck"),
            )
        assertTrue(openSession.indexOf("session.clientNextSeq =") < openSession.indexOf("session.socket = socket"))
        assertTrue(openSession.contains("retainAndEnqueueSynAck(session)"))
        assertTrue(engine.contains("ensureTcpDownstreamReader(key, session)"))
        assertTrue(engine.contains("session.handshakeDeadlineMs = monotonicTimeMs()"))
        assertTrue(engine.contains("TCP handshake timed out for"))
        assertFalse(engine.contains("session.handshake.await(HANDSHAKE_TIMEOUT_MS)"))
        assertTrue(engine.contains("seq = session.serverIsn"))
        assertTrue(retainedSyn.contains("flags = Packet.SYN or Packet.ACK"))
        assertTrue(retainedSyn.contains("session.retransmissions.markQueued(reservation, monotonicTimeMs())"))
        assertTrue(retransmission.contains("if (due.flags and Packet.SYN != 0)"))
        assertTrue(retransmission.contains("TcpSegmentSizer.maxPayloadBytes(mtu, session.ipv6)"))
        assertTrue(retransmission.contains("SERVER_WINDOW_SCALE"))
        assertTrue(engine.contains("handshake.cancel()"))
        assertFalse(engine.contains("session.handshakeComplete = true"))
    }

    private fun resolve(vararg paths: String): File =
        paths.map { File(it) }.firstOrNull { it.isFile }
            ?: error("file not found from cwd=${File(".").absolutePath}: ${paths.toList()}")
}
