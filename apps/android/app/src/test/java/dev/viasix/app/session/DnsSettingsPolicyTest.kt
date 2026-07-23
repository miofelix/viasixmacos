package dev.viasix.app.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DnsSettingsPolicyTest {
    @Test
    fun normalizesNumericIpv4AndIpv6WithoutResolvingHostnames() {
        assertEquals("1.1.1.1", DnsSettingsPolicy.normalizeServer("001.001.001.001"))
        assertEquals("2606:4700:4700::1111", DnsSettingsPolicy.normalizeServer("2606:4700:4700::1111"))
        assertNull(DnsSettingsPolicy.normalizeServer("dns.google"))
        assertNull(DnsSettingsPolicy.normalizeServer("999.1.1.1"))
        assertFalse(DnsSettingsPolicy.isValidServer("1.1.1"))
        assertTrue(DnsSettingsPolicy.isValidServer("8.8.8.8"))
    }

    @Test
    fun wireModeDefaultsToProxyForPrivacy() {
        assertEquals(DnsRoutingMode.PROXY, DnsRoutingMode.parse(null))
        assertEquals(DnsRoutingMode.PROXY, DnsRoutingMode.parse("unknown"))
        assertEquals(DnsRoutingMode.DIRECT, DnsRoutingMode.parse("direct"))
        assertFalse(
            DnsSettingsPolicy.shouldUseProtectedDirect(
                destinationPort = 53,
                mode = DnsRoutingMode.PROXY,
            ),
        )
        assertTrue(
            DnsSettingsPolicy.shouldUseProtectedDirect(
                destinationPort = 53,
                mode = DnsRoutingMode.DIRECT,
            ),
        )
        assertFalse(
            DnsSettingsPolicy.shouldUseProtectedDirect(
                destinationPort = 443,
                mode = DnsRoutingMode.DIRECT,
            ),
        )
    }
}
