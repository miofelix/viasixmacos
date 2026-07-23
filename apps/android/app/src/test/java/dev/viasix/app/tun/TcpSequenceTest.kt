package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TcpSequenceTest {
    @Test
    fun advanceWrapsAcrossUnsigned32BitBoundary() {
        assertEquals(1L, TcpSequence.advance(0xffff_ffffL, payloadLength = 1, fin = true))
        assertEquals(0L, TcpSequence.advance(0xffff_ffffL, syn = true))
    }

    @Test
    fun duplicatePrefixIsSkippedAcrossWrap() {
        assertEquals(
            2,
            TcpSequence.consumedPayloadPrefix(
                segmentStart = 0xffff_ffffL,
                payloadLength = 4,
                nextExpected = 1L,
            ),
        )
    }

    @Test
    fun outOfOrderFutureSegmentIsRejected() {
        assertNull(
            TcpSequence.consumedPayloadPrefix(
                segmentStart = 105L,
                payloadLength = 4,
                nextExpected = 100L,
            ),
        )
    }
}
