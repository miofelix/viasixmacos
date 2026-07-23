package dev.viasix.app.tun

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpRetransmissionQueueTest {
    @Test
    fun cumulativeAndPartialAcknowledgementsReleaseRetainedBytes() {
        val queue = queue()
        val first = queue.reserve(100L, Packet.PSH or Packet.ACK, byteArrayOf(1, 2, 3, 4))!!
        val second = queue.reserve(104L, Packet.PSH or Packet.ACK, byteArrayOf(5, 6, 7, 8))!!

        assertTrue(queue.markQueued(first, nowMs = 0L))
        assertTrue(queue.markQueued(second, nowMs = 0L))
        assertTrue(queue.acknowledge(acknowledgement = 106L, nowMs = 100L))

        val due = queue.pollDue(nowMs = 1_100L) as TcpRetransmissionQueue.PollResult.Retransmit
        assertEquals(106L, due.sequence)
        assertArrayEquals(byteArrayOf(7, 8), due.payload)
    }

    @Test
    fun retransmissionTimeoutBacksOffAndEventuallyExhausts() {
        val queue = queue(maxRetransmissions = 2)
        val reservation = queue.reserve(10L, Packet.PSH or Packet.ACK, byteArrayOf(1))!!
        queue.markQueued(reservation, nowMs = 0L)

        assertNull(queue.pollDue(nowMs = 999L))
        val first = queue.pollDue(nowMs = 1_000L) as TcpRetransmissionQueue.PollResult.Retransmit
        assertEquals(1, first.attempt)
        assertNull(queue.pollDue(nowMs = 2_999L))
        val second = queue.pollDue(nowMs = 3_000L) as TcpRetransmissionQueue.PollResult.Retransmit
        assertEquals(2, second.attempt)
        assertNull(queue.pollDue(nowMs = 6_999L))
        assertSame(TcpRetransmissionQueue.PollResult.Exhausted, queue.pollDue(nowMs = 7_000L))
    }

    @Test
    fun deferredSendDoesNotConsumeRetransmissionAttemptOrBackoff() {
        val queue = queue(maxRetransmissions = 1)
        val reservation = queue.reserve(10L, Packet.ACK, byteArrayOf(1))!!
        queue.markQueued(reservation, nowMs = 0L)

        val first = queue.pollDue(nowMs = 1_000L) as TcpRetransmissionQueue.PollResult.Retransmit
        assertEquals(1, first.attempt)
        assertTrue(queue.deferRetransmission(first, nowMs = 1_000L))
        val retried = queue.pollDue(nowMs = 1_001L) as TcpRetransmissionQueue.PollResult.Retransmit

        assertEquals(1, retried.attempt)
        assertNull(queue.pollDue(nowMs = 3_000L))
        assertSame(TcpRetransmissionQueue.PollResult.Exhausted, queue.pollDue(nowMs = 3_001L))
    }

    @Test
    fun queuedMarkerMayArriveAfterFastAcknowledgement() {
        val queue = queue()
        val reservation = queue.reserve(200L, Packet.PSH or Packet.ACK, byteArrayOf(1, 2))!!

        assertTrue(queue.acknowledge(acknowledgement = 202L, nowMs = 1L))
        assertFalse(queue.markQueued(reservation, nowMs = 2L))
        assertTrue(queue.awaitEmpty(timeoutMs = 0L))
    }

    @Test
    fun sequenceWrapTrimsAcknowledgedPrefix() {
        val queue = queue()
        val reservation =
            queue.reserve(
                sequence = 0xffff_fffeL,
                flags = Packet.PSH or Packet.ACK,
                payload = byteArrayOf(1, 2, 3, 4),
            )!!
        queue.markQueued(reservation, nowMs = 0L)

        assertTrue(queue.acknowledge(acknowledgement = 0L, nowMs = 10L))
        val due = queue.pollDue(nowMs = 1_010L) as TcpRetransmissionQueue.PollResult.Retransmit
        assertEquals(0L, due.sequence)
        assertArrayEquals(byteArrayOf(3, 4), due.payload)
    }

    @Test
    fun discontinuousOrOversizedRetentionIsRejected() {
        val queue = queue(maxRetainedBytes = 4)

        assertTrue(queue.reserve(50L, Packet.ACK, byteArrayOf(1, 2)) != null)
        assertNull(queue.reserve(53L, Packet.ACK, byteArrayOf(3)))
        assertNull(queue.reserve(52L, Packet.ACK, byteArrayOf(3, 4, 5)))
    }

    @Test
    fun finConsumesSequenceSpaceAndIsRetainedUntilAcknowledged() {
        val queue = queue()
        val reservation =
            queue.reserve(
                sequence = 0xffff_ffffL,
                flags = Packet.FIN or Packet.ACK,
                payload = ByteArray(0),
            )!!
        queue.markQueued(reservation, nowMs = 0L)

        val due = queue.pollDue(nowMs = 1_000L) as TcpRetransmissionQueue.PollResult.Retransmit
        assertEquals(0xffff_ffffL, due.sequence)
        assertEquals(Packet.FIN or Packet.ACK, due.flags)
        assertTrue(queue.acknowledge(acknowledgement = 0L, nowMs = 1_001L))
        assertTrue(queue.awaitEmpty(timeoutMs = 0L))
    }

    @Test
    fun synConsumesSequenceSpaceAndIsRetainedUntilAcknowledged() {
        val queue = queue()
        val reservation =
            queue.reserve(
                sequence = 100L,
                flags = Packet.SYN or Packet.ACK,
                payload = ByteArray(0),
            )!!
        queue.markQueued(reservation, nowMs = 0L)

        val due = queue.pollDue(nowMs = 1_000L) as TcpRetransmissionQueue.PollResult.Retransmit
        assertEquals(100L, due.sequence)
        assertEquals(Packet.SYN or Packet.ACK, due.flags)
        assertTrue(queue.acknowledge(acknowledgement = 101L, nowMs = 1_001L))
        assertTrue(queue.awaitEmpty(timeoutMs = 0L))
    }

    @Test
    fun thirdDuplicateAcknowledgementTriggersOneFastRetransmission() {
        val queue = queue()
        val reservation = queue.reserve(100L, Packet.PSH or Packet.ACK, byteArrayOf(1, 2))!!
        queue.markQueued(reservation, nowMs = 0L)

        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 10L))
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 20L))
        val due =
            queue.noteDuplicateAcknowledgement(100L, nowMs = 30L)
                as TcpRetransmissionQueue.PollResult.Retransmit

        assertEquals(100L, due.sequence)
        assertArrayEquals(byteArrayOf(1, 2), due.payload)
        assertEquals(1, due.attempt)
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 40L))
    }

    @Test
    fun advertisedWindowChangeResetsDuplicateAcknowledgementCount() {
        val queue = queue()
        val reservation = queue.reserve(100L, Packet.ACK, byteArrayOf(1, 2))!!
        queue.markQueued(reservation, nowMs = 0L)

        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 10L, advertisedWindow = 1_000))
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 20L, advertisedWindow = 1_000))
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 30L, advertisedWindow = 2_000))
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 40L, advertisedWindow = 2_000))
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 50L, advertisedWindow = 2_000))
        val due =
            queue.noteDuplicateAcknowledgement(100L, nowMs = 60L, advertisedWindow = 2_000)

        assertEquals(100L, due!!.sequence)
        assertEquals(1, due.attempt)
    }

    @Test
    fun idleAcknowledgementWindowProvidesNextDuplicateBaseline() {
        val queue = queue()

        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 0L, advertisedWindow = 1_000))
        val reservation = queue.reserve(100L, Packet.ACK, byteArrayOf(1, 2))!!
        queue.markQueued(reservation, nowMs = 1L)
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 10L, advertisedWindow = 2_000))
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 20L, advertisedWindow = 2_000))
        assertNull(queue.noteDuplicateAcknowledgement(100L, nowMs = 30L, advertisedWindow = 2_000))
        val due =
            queue.noteDuplicateAcknowledgement(100L, nowMs = 40L, advertisedWindow = 2_000)

        assertEquals(100L, due!!.sequence)
    }

    @Test
    fun advancingAcknowledgementResetsFastRetransmitForNewOldestSegment() {
        val queue = queue()
        val first = queue.reserve(200L, Packet.PSH or Packet.ACK, byteArrayOf(1, 2))!!
        val second = queue.reserve(202L, Packet.PSH or Packet.ACK, byteArrayOf(3, 4))!!
        queue.markQueued(first, nowMs = 0L)
        queue.markQueued(second, nowMs = 0L)
        repeat(3) { queue.noteDuplicateAcknowledgement(200L, nowMs = 10L + it) }

        assertTrue(queue.acknowledge(acknowledgement = 202L, nowMs = 100L))
        assertNull(queue.noteDuplicateAcknowledgement(202L, nowMs = 110L))
        assertNull(queue.noteDuplicateAcknowledgement(202L, nowMs = 120L))
        val due = queue.noteDuplicateAcknowledgement(202L, nowMs = 130L)

        assertEquals(202L, due!!.sequence)
        assertArrayEquals(byteArrayOf(3, 4), due.payload)
    }

    private fun queue(
        maxRetransmissions: Int = 5,
        maxRetainedBytes: Int = 16,
    ) =
        TcpRetransmissionQueue(
            baseRtoMs = 1_000L,
            maxRtoMs = 8_000L,
            maxRetransmissions = maxRetransmissions,
            maxRetainedBytes = maxRetainedBytes,
        )
}
