package dev.viasix.app.session

import dev.viasix.core.profile.ProfileSummary
import dev.viasix.core.profile.ProxyEntrySummary
import dev.viasix.core.projection.RoutingMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Drives real [SessionStartGate] — shared by Overview connect and Quick Settings tile.
 */
class SessionStartGateTest {
    private val goodNode = "2001:db8::1"
    private val managedSummary =
        ProfileSummary(
            proxyCount = 1,
            primary =
                ProxyEntrySummary(
                    name = "cf-vless",
                    type = "vless",
                    server = "example.com",
                    port = 443,
                ),
            hasXViasix = true,
            primaryServerMarker = "selected-ip",
            warnings = emptyList(),
        )

    @Test
    fun directModeAlwaysOk() {
        val result =
            SessionStartGate.evaluate(
                RoutingMode.DIRECT,
                selectedAddress = "not-an-ip",
                summary =
                    ProfileSummary(
                        proxyCount = 0,
                        primary = null,
                        hasXViasix = false,
                        primaryServerMarker = null,
                        warnings = emptyList(),
                    ),
            )
        assertEquals(SessionStartGate.Result.Ok, result)
    }

    @Test
    fun onlySelectedModeRequiresAtLeastOneAppEvenInDirectMode() {
        val result =
            SessionStartGate.evaluate(
                RoutingMode.DIRECT,
                selectedAddress = "not-an-ip",
                summary = managedSummary,
                appRoutingMode = AppRoutingMode.ONLY_SELECTED,
                selectedAppPackages = emptyList(),
            )

        assertTrue(result is SessionStartGate.Result.Blocked)
        assertEquals("settings", (result as SessionStartGate.Result.Blocked).sectionWire)
    }

    @Test
    fun onlySelectedModeRejectsInvalidPackageNames() {
        val result =
            SessionStartGate.evaluate(
                RoutingMode.DIRECT,
                selectedAddress = "not-an-ip",
                summary = managedSummary,
                appRoutingMode = AppRoutingMode.ONLY_SELECTED,
                selectedAppPackages = listOf("not-a-package"),
            )

        assertTrue(result is SessionStartGate.Result.Blocked)
    }

    @Test
    fun invalidDnsServerIsBlockedInSettings() {
        val result =
            SessionStartGate.evaluate(
                RoutingMode.DIRECT,
                selectedAddress = goodNode,
                summary = managedSummary,
                dnsServer = "dns.example.com",
            )

        assertTrue(result is SessionStartGate.Result.Blocked)
        assertEquals("settings", (result as SessionStartGate.Result.Blocked).sectionWire)
        assertTrue(result.message.contains("DNS"))
    }

    @Test
    fun proxyOnlyModeDoesNotRequireTunDnsSettings() {
        val result =
            SessionStartGate.evaluate(
                RoutingMode.DIRECT,
                selectedAddress = goodNode,
                summary = managedSummary,
                dnsServer = "not-used.example",
                fullTunnel = false,
            )

        assertEquals(SessionStartGate.Result.Ok, result)
    }

    @Test
    fun invalidVpnMtuIsBlockedInSettingsForEveryVpnMode() {
        for (fullTunnel in listOf(true, false)) {
            val result =
                SessionStartGate.evaluate(
                    RoutingMode.DIRECT,
                    selectedAddress = goodNode,
                    summary = managedSummary,
                    fullTunnel = fullTunnel,
                    vpnMtu = "1279",
                )

            assertTrue(result is SessionStartGate.Result.Blocked)
            assertEquals("settings", (result as SessionStartGate.Result.Blocked).sectionWire)
            assertTrue(result.message.contains("MTU"))
        }
    }

    @Test
    fun nonTunnelIpv6ModesRejectIpv6Dns() {
        for (mode in listOf(Ipv6RoutingMode.BLOCK, Ipv6RoutingMode.BYPASS)) {
            val result =
                SessionStartGate.evaluate(
                    routingMode = RoutingMode.DIRECT,
                    selectedAddress = goodNode,
                    summary = managedSummary,
                    dnsServer = "2606:4700:4700::1111",
                    ipv6RoutingMode = mode,
                )

            assertTrue(result is SessionStartGate.Result.Blocked)
            assertEquals("settings", (result as SessionStartGate.Result.Blocked).sectionWire)
            assertTrue(result.message.contains("IPv4 DNS"))
        }
    }

    @Test
    fun nonTunnelIpv6ModesAllowIpv4Dns() {
        for (mode in listOf(Ipv6RoutingMode.BLOCK, Ipv6RoutingMode.BYPASS)) {
            val result =
                SessionStartGate.evaluate(
                    routingMode = RoutingMode.DIRECT,
                    selectedAddress = goodNode,
                    summary = managedSummary,
                    dnsServer = "1.1.1.1",
                    ipv6RoutingMode = mode,
                )

            assertEquals(SessionStartGate.Result.Ok, result)
        }
    }

    @Test
    fun ruleModeBlocksWithoutIpv6() {
        val result =
            SessionStartGate.evaluate(RoutingMode.RULE, "invalid", managedSummary)
        assertTrue(result is SessionStartGate.Result.Blocked)
        val blocked = result as SessionStartGate.Result.Blocked
        assertEquals("nodes", blocked.sectionWire)
        assertTrue(blocked.message.contains("IPv6"))
    }

    @Test
    fun ruleModeBlocksWithoutPrimaryProxy() {
        val empty =
            ProfileSummary(
                proxyCount = 0,
                primary = null,
                hasXViasix = false,
                primaryServerMarker = null,
                warnings = emptyList(),
            )
        val result = SessionStartGate.evaluate(RoutingMode.GLOBAL, goodNode, empty)
        assertTrue(result is SessionStartGate.Result.Blocked)
        assertEquals("profiles", (result as SessionStartGate.Result.Blocked).sectionWire)
    }

    @Test
    fun ruleModeOkWithNodeAndPrimary() {
        val result = SessionStartGate.evaluate(RoutingMode.RULE, goodNode, managedSummary)
        assertEquals(SessionStartGate.Result.Ok, result)
    }
}
