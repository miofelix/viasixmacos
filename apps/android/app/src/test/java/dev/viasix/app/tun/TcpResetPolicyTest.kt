package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TcpResetPolicyTest {
    @Test
    fun exactSequenceClosesConnection() {
        assertEquals(
            TcpResetPolicy.Action.CLOSE,
            TcpResetPolicy.classify(sequence = 100L, nextExpected = 100L),
        )
    }

    @Test
    fun nonExactSequenceInsideReceiveWindowChallenges() {
        assertEquals(
            TcpResetPolicy.Action.CHALLENGE_ACK,
            TcpResetPolicy.classify(sequence = 101L, nextExpected = 100L),
        )
        assertEquals(
            TcpResetPolicy.Action.CHALLENGE_ACK,
            TcpResetPolicy.classify(sequence = 65_634L, nextExpected = 100L),
        )
    }

    @Test
    fun sequenceOutsideReceiveWindowIsDropped() {
        assertEquals(
            TcpResetPolicy.Action.DROP,
            TcpResetPolicy.classify(sequence = 65_635L, nextExpected = 100L),
        )
        assertEquals(
            TcpResetPolicy.Action.DROP,
            TcpResetPolicy.classify(sequence = 99L, nextExpected = 100L),
        )
    }

    @Test
    fun receiveWindowClassificationHandlesSequenceWrap() {
        assertEquals(
            TcpResetPolicy.Action.CHALLENGE_ACK,
            TcpResetPolicy.classify(sequence = 1L, nextExpected = 0xffff_fffeL),
        )
        assertEquals(
            TcpResetPolicy.Action.CLOSE,
            TcpResetPolicy.classify(sequence = 0L, nextExpected = 0L),
        )
    }

    @Test
    fun zeroWindowOnlyAcceptsExactReset() {
        assertEquals(
            TcpResetPolicy.Action.DROP,
            TcpResetPolicy.classify(sequence = 101L, nextExpected = 100L, receiveWindow = 0),
        )
    }

    @Test
    fun rejectsInvalidReceiveWindow() {
        assertThrows(IllegalArgumentException::class.java) {
            TcpResetPolicy.classify(sequence = 1L, nextExpected = 1L, receiveWindow = 65_536)
        }
    }
}
