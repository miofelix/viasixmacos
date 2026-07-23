package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class TcpWindowScaleTest {
    @Test
    fun receivedShiftIsClampedToRfcMaximum() {
        assertEquals(0, TcpWindowScale.normalize(0))
        assertEquals(14, TcpWindowScale.normalize(14))
        assertEquals(14, TcpWindowScale.normalize(255))
    }

    @Test
    fun expandsUnsignedWindowWithoutOverflow() {
        assertEquals(65_535, TcpWindowScale.expand(advertisedWindow = 65_535, shift = 0))
        assertEquals(131_070, TcpWindowScale.expand(advertisedWindow = 65_535, shift = 1))
        assertEquals(1_073_725_440, TcpWindowScale.expand(advertisedWindow = 65_535, shift = 14))
    }

    @Test
    fun rejectsInvalidInputs() {
        assertThrows(IllegalArgumentException::class.java) { TcpWindowScale.normalize(-1) }
        assertThrows(IllegalArgumentException::class.java) {
            TcpWindowScale.expand(advertisedWindow = 65_536, shift = 0)
        }
        assertThrows(IllegalArgumentException::class.java) {
            TcpWindowScale.expand(advertisedWindow = 1, shift = 15)
        }
    }
}
