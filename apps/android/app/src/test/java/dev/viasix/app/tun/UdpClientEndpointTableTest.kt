package dev.viasix.app.tun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

/**
 * Exercises real [UdpClientEndpointTable]: per-client (not per-remote) registration,
 * limits, and idle expiry — the demux model for general UDP ASSOCIATE.
 */
class UdpClientEndpointTableTest {
    private val clientA = InetAddress.getByName("10.10.0.2")
    private val clientB = InetAddress.getByName("10.10.0.3")

    @Test
    fun twoLocalPortsAreIndependentEndpoints() {
        val table = UdpClientEndpointTable(maxEntries = 8, idleTimeoutMs = 60_000)
        val e1 = UdpClientEndpointTable.Endpoint(clientA, 50000, ipv6 = false)
        val e2 = UdpClientEndpointTable.Endpoint(clientA, 50001, ipv6 = false)
        assertTrue(table.noteActivity(e1))
        assertTrue(table.noteActivity(e2))
        assertEquals(2, table.size)
        assertTrue(table.contains(e1))
        assertTrue(table.contains(e2))
        // Concurrent flows from different local ports must not share one reverse slot.
        assertFalse(e1.key() == e2.key())
    }

    @Test
    fun enforcesMaxClientsOnNewEndpoints() {
        val table = UdpClientEndpointTable(maxEntries = 2, idleTimeoutMs = 60_000)
        assertTrue(table.noteActivity(UdpClientEndpointTable.Endpoint(clientA, 1000)))
        assertTrue(table.noteActivity(UdpClientEndpointTable.Endpoint(clientA, 1001)))
        assertFalse(table.noteActivity(UdpClientEndpointTable.Endpoint(clientB, 1002)))
        // Refresh existing still ok
        assertTrue(table.noteActivity(UdpClientEndpointTable.Endpoint(clientA, 1000)))
    }

    @Test
    fun purgeExpired_dropsIdleClients() {
        var now = 1_000L
        val table =
            UdpClientEndpointTable(
                maxEntries = 8,
                idleTimeoutMs = 100,
                clock = { now },
            )
        val e = UdpClientEndpointTable.Endpoint(clientA, 4000)
        assertTrue(table.noteActivity(e))
        now = 1_250L
        val dropped = table.purgeExpired()
        assertEquals(1, dropped.size)
        assertEquals(e.port, dropped[0].port)
        assertEquals(0, table.size)
    }

    @Test
    fun ipv6FlagIsPartOfKey() {
        val table = UdpClientEndpointTable()
        val v4 = UdpClientEndpointTable.Endpoint(clientA, 53, ipv6 = false)
        val v6 = UdpClientEndpointTable.Endpoint(clientA, 53, ipv6 = true)
        assertTrue(table.noteActivity(v4))
        assertTrue(table.noteActivity(v6))
        assertEquals(2, table.size)
        assertFalse(v4.key() == v6.key())
    }

    @Test
    fun remove_clearsEndpoint() {
        val table = UdpClientEndpointTable()
        val e = UdpClientEndpointTable.Endpoint(clientA, 9999)
        assertTrue(table.noteActivity(e))
        table.remove(e)
        assertFalse(table.contains(e))
    }
}
