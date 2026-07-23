package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class Ipv6RoutingModeTest {
    @Test
    fun unknownAndMissingValuesFailClosedToTunnel() {
        assertEquals(Ipv6RoutingMode.TUNNEL, Ipv6RoutingMode.parse(null))
        assertEquals(Ipv6RoutingMode.TUNNEL, Ipv6RoutingMode.parse("unknown"))
    }

    @Test
    fun bypassCopyMakesExposureExplicit() {
        assertTrue(Ipv6RoutingMode.BYPASS.detail.contains("真实 IPv6"))
        assertTrue(Ipv6RoutingMode.TUNNEL.detail.contains("中止连接"))
    }
}
