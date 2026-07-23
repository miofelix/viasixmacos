package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalNetworkBypassPolicyTest {
    @Test
    fun coversPrivateLinkLocalLoopbackAndDiscoveryDestinations() {
        assertEquals(
            listOf(
                "10.0.0.0/8",
                "127.0.0.0/8",
                "169.254.0.0/16",
                "172.16.0.0/12",
                "192.168.0.0/16",
                "224.0.0.0/4",
                "255.255.255.255/32",
            ),
            LocalNetworkBypassPolicy.IPV4_PREFIXES,
        )
        assertEquals(
            listOf("::1/128", "fc00::/7", "fe80::/10", "ff00::/8"),
            LocalNetworkBypassPolicy.IPV6_PREFIXES,
        )
        assertTrue(LocalNetworkBypassPolicy.IPV4_PREFIXES.none { it == "0.0.0.0/0" })
        assertTrue(LocalNetworkBypassPolicy.IPV6_PREFIXES.none { it == "::/0" })
    }
}
