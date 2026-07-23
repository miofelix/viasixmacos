package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpSendWindowTest {
    @Test
    fun allowanceTracksBytesInFlightAndAcknowledgements() {
        val window = TcpSendWindow()

        assertTrue(window.update(acknowledgement = 100L, advertisedWindow = 1_000, nextSequence = 100L))
        assertEquals(1_000, window.awaitAllowance(maxBytes = 16_384, timeoutMs = 0L))
        assertTrue(window.recordSent(sequence = 100L, payloadLength = 600))
        assertEquals(400, window.awaitAllowance(maxBytes = 16_384, timeoutMs = 0L))
        assertTrue(window.update(acknowledgement = 700L, advertisedWindow = 1_000, nextSequence = 700L))
        assertEquals(1_000, window.awaitAllowance(maxBytes = 16_384, timeoutMs = 0L))
    }

    @Test
    fun zeroWindowAndAcknowledgementBeyondSentDataDoNotReleaseReads() {
        val window = TcpSendWindow()

        assertTrue(window.update(acknowledgement = 50L, advertisedWindow = 0, nextSequence = 50L))
        assertEquals(0, window.awaitAllowance(maxBytes = 1_024, timeoutMs = 0L))
        assertFalse(window.update(acknowledgement = 60L, advertisedWindow = 1_024, nextSequence = 50L))
        assertEquals(0, window.awaitAllowance(maxBytes = 1_024, timeoutMs = 0L))
    }

    @Test
    fun sequenceWrapKeepsInFlightAccountingCorrect() {
        val window = TcpSendWindow()

        assertTrue(
            window.update(
                acknowledgement = 0xffff_ff00L,
                advertisedWindow = 1_024,
                nextSequence = 0xffff_ff00L,
            ),
        )
        assertTrue(window.recordSent(sequence = 0xffff_ff00L, payloadLength = 256))
        assertEquals(768, window.awaitAllowance(maxBytes = 1_024, timeoutMs = 0L))
    }

    @Test
    fun sentReservationAcceptsFastAcknowledgementBeforeExternalSequenceAdvances() {
        val window = TcpSendWindow()

        assertTrue(window.update(acknowledgement = 100L, advertisedWindow = 1_000, nextSequence = 100L))
        assertTrue(window.recordSent(sequence = 100L, payloadLength = 300))
        assertTrue(window.update(acknowledgement = 400L, advertisedWindow = 1_000, nextSequence = 100L))
        assertEquals(1_000, window.awaitAllowance(maxBytes = 1_024, timeoutMs = 0L))
    }

    @Test
    fun backwardAcknowledgementAndMismatchedReservationAreRejected() {
        val window = TcpSendWindow()

        assertTrue(window.update(acknowledgement = 1_000L, advertisedWindow = 2_000, nextSequence = 1_000L))
        assertFalse(window.recordSent(sequence = 1_001L, payloadLength = 100))
        assertTrue(window.recordSent(sequence = 1_000L, payloadLength = 100))
        assertTrue(window.update(acknowledgement = 1_050L, advertisedWindow = 2_000, nextSequence = 1_100L))
        assertFalse(window.update(acknowledgement = 1_025L, advertisedWindow = 2_000, nextSequence = 1_100L))
        assertEquals(1_950, window.awaitAllowance(maxBytes = 2_000, timeoutMs = 0L))
    }
}
