package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class UnderlyingNetworkStateTest {
    @Test
    fun presentationDistinguishesTransportAndValidation() {
        assertEquals(
            "Wi-Fi · 已联网",
            UnderlyingNetworkPresentation.label(
                wifi = true,
                cellular = false,
                ethernet = false,
                validated = true,
            ),
        )
        assertEquals(
            "蜂窝网络 · 待验证",
            UnderlyingNetworkPresentation.label(
                wifi = false,
                cellular = true,
                ethernet = false,
                validated = false,
            ),
        )
        assertEquals(
            "以太网 · 已联网",
            UnderlyingNetworkPresentation.label(
                wifi = false,
                cellular = false,
                ethernet = true,
                validated = true,
            ),
        )
    }

    @Test
    fun delayedLossForOldNetworkDoesNotClearNewSelection() {
        val selectedA = UnderlyingNetworkSelection<String>().updated("network-a", "Wi-Fi · 已联网")
        val selectedB = selectedA.updated("network-b", "蜂窝网络 · 已联网")

        assertSame(selectedB, selectedB.lost("network-a"))
    }

    @Test
    fun currentNetworkLossMovesSelectionIntoHandoverState() {
        val selected =
            UnderlyingNetworkSelection<String>()
                .updated("network-a", "Wi-Fi · 已联网")
                .lost("network-a")

        assertNull(selected.network)
        assertEquals("网络切换中", selected.label)
    }
}
