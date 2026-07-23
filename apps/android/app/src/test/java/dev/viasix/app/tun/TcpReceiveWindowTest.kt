package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpReceiveWindowTest {
    @Test
    fun emptySegmentMustStartInsideNonZeroWindow() {
        assertTrue(accepts(sequence = 100L, nextExpected = 100L))
        assertTrue(accepts(sequence = 65_634L, nextExpected = 100L))
        assertFalse(accepts(sequence = 65_635L, nextExpected = 100L))
        assertFalse(accepts(sequence = 99L, nextExpected = 100L))
    }

    @Test
    fun dataSegmentMayStartBeforeWindowWhenItsEndOverlaps() {
        assertTrue(accepts(sequence = 99L, payloadLength = 2, nextExpected = 100L))
        assertFalse(accepts(sequence = 98L, payloadLength = 2, nextExpected = 100L))
    }

    @Test
    fun finConsumesOneSequenceNumberForOverlap() {
        assertTrue(accepts(sequence = 100L, fin = true, nextExpected = 100L))
        assertFalse(accepts(sequence = 99L, fin = true, nextExpected = 100L))
    }

    @Test
    fun zeroWindowOnlyAcceptsExactEmptySegment() {
        assertTrue(accepts(sequence = 100L, nextExpected = 100L, receiveWindow = 0))
        assertFalse(accepts(sequence = 101L, nextExpected = 100L, receiveWindow = 0))
        assertFalse(accepts(sequence = 100L, payloadLength = 1, nextExpected = 100L, receiveWindow = 0))
    }

    @Test
    fun sequenceWindowHandlesThirtyTwoBitWrap() {
        assertTrue(accepts(sequence = 1L, nextExpected = 0xffff_fffeL, receiveWindow = 4))
        assertFalse(accepts(sequence = 2L, nextExpected = 0xffff_fffeL, receiveWindow = 4))
        assertTrue(
            accepts(
                sequence = 0xffff_fffdL,
                payloadLength = 2,
                nextExpected = 0xffff_fffeL,
                receiveWindow = 4,
            ),
        )
    }

    @Test
    fun rejectsInvalidLengthsAndWindows() {
        assertThrows(IllegalArgumentException::class.java) {
            accepts(sequence = 1L, payloadLength = -1, nextExpected = 1L)
        }
        assertThrows(IllegalArgumentException::class.java) {
            accepts(sequence = 1L, nextExpected = 1L, receiveWindow = 65_536)
        }
    }

    private fun accepts(
        sequence: Long,
        payloadLength: Int = 0,
        fin: Boolean = false,
        nextExpected: Long,
        receiveWindow: Int = Packet.TCP_WINDOW_SIZE,
    ): Boolean =
        TcpReceiveWindow.accepts(
            sequence = sequence,
            payloadLength = payloadLength,
            fin = fin,
            nextExpected = nextExpected,
            receiveWindow = receiveWindow,
        )
}
