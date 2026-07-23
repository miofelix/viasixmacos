package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

/**
 * Exercises real [UdpNatTable] session limits, reverse lookup, and idle expiry.
 */
class UdpNatTableTest {
    private val client = InetAddress.getByName("10.10.0.2")
    private val remoteA = InetAddress.getByName("1.1.1.1")
    private val remoteB = InetAddress.getByName("8.8.8.8")

    @Test
    fun observeAndLookup_roundTrip() {
        val table = UdpNatTable(maxEntries = 8, idleTimeoutMs = 60_000)
        assertTrue(table.observeOutbound(client, 50000, remoteA, 53, ipv6 = false))
        val hit = table.lookupInbound(remoteA, 53)
        assertNotNull(hit)
        assertEquals(client, hit!!.ip)
        assertEquals(50000, hit.port)
        assertFalse(hit.ipv6)
    }

    @Test
    fun observeOutbound_marksIpv6Flag() {
        val c6 = InetAddress.getByName("fd00:10:10::2")
        val r6 = InetAddress.getByName("2001:db8::53")
        val table = UdpNatTable()
        assertTrue(table.observeOutbound(c6, 53000, r6, 53, ipv6 = true))
        val hit = table.lookupInbound(r6, 53)!!
        assertTrue(hit.ipv6)
        assertEquals(c6, hit.ip)
    }

    @Test
    fun enforcesMaxEntriesOnNewFlows() {
        val table = UdpNatTable(maxEntries = 2, idleTimeoutMs = 60_000)
        assertTrue(table.observeOutbound(client, 1000, remoteA, 443))
        assertTrue(table.observeOutbound(client, 1001, remoteB, 443))
        assertFalse(table.observeOutbound(client, 1002, InetAddress.getByName("9.9.9.9"), 443))
        // Refresh existing flow still allowed
        assertTrue(table.observeOutbound(client, 1000, remoteA, 443))
    }

    @Test
    fun purgeExpired_dropsIdleFlows() {
        var now = 1_000L
        val table =
            UdpNatTable(
                maxEntries = 8,
                idleTimeoutMs = 100,
                clock = { now },
            )
        assertTrue(table.observeOutbound(client, 4000, remoteA, 443))
        now = 1_250L // past idle timeout
        assertNull(table.lookupInbound(remoteA, 443))
        assertEquals(0, table.size)
    }

    @Test
    fun lookupInbound_unknownRemoteIsNull() {
        val table = UdpNatTable()
        assertNull(table.lookupInbound(remoteA, 9999))
    }
}
