package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TcpClosedStateResetTest {
    @Test
    fun acknowledgedSegmentUsesAcknowledgementAsResetSequence() {
        val reply = TcpClosedStateReset.forSegment(segment(seq = 10L, ack = 900L, flags = Packet.ACK))

        assertEquals(900L, reply?.sequence)
        assertEquals(0L, reply?.acknowledgement)
        assertEquals(Packet.RST, reply?.flags)
    }

    @Test
    fun synAndPayloadAdvanceResetAcknowledgement() {
        val reply =
            TcpClosedStateReset.forSegment(
                segment(
                    seq = 100L,
                    flags = Packet.SYN or Packet.FIN,
                    payloadLength = 20,
                ),
            )

        assertEquals(0L, reply?.sequence)
        assertEquals(122L, reply?.acknowledgement)
        assertEquals(Packet.RST or Packet.ACK, reply?.flags)
    }

    @Test
    fun acknowledgementWrapsAtThirtyTwoBits() {
        val reply =
            TcpClosedStateReset.forSegment(
                segment(
                    seq = 0xffff_fffeL,
                    flags = Packet.FIN,
                    payloadLength = 2,
                ),
            )

        assertEquals(1L, reply?.acknowledgement)
    }

    @Test
    fun resetNeverAnswersAnotherReset() {
        assertNull(TcpClosedStateReset.forSegment(segment(seq = 1L, flags = Packet.RST)))
        assertNull(
            TcpClosedStateReset.forSegment(
                segment(seq = 1L, flags = Packet.SYN or Packet.RST),
            ),
        )
    }

    private fun segment(
        seq: Long,
        ack: Long = 0L,
        flags: Int,
        payloadLength: Int = 0,
    ): Packet.Tcp =
        Packet.Tcp(
            sourcePort = 12_345,
            destPort = 443,
            seq = seq,
            ack = ack,
            dataOffset = Packet.TCP_HEADER_SIZE,
            flags = flags,
            window = 65_535,
            payloadOffset = Packet.TCP_HEADER_SIZE,
            payloadLength = payloadLength,
        )
}
