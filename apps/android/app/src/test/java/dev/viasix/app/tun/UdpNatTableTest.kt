package dev.viasix.app.tun

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

/**
 * Regression: production demux must NOT reverse-NAT solely by remote host:port
 * (last-writer-wins). Two local ports talking to the same remote must remain distinct.
 *
 * DNS in proxy mode and general UDP use per-client ASSOCIATE
 * ([UdpClientEndpointTable]); explicit direct DNS uses per-query protected sockets.
 */
class UdpDemuxContractTest {
    @Test
    fun concurrentLocalPortsToSameRemote_haveDistinctClientKeys() {
        val client = InetAddress.getByName("10.10.0.2")
        // Two DNS-like local ports (or two QUIC sockets) toward 1.1.1.1:53 / CDN:443
        val a = UdpClientEndpointTable.Endpoint(client, 53001, ipv6 = false)
        val b = UdpClientEndpointTable.Endpoint(client, 53002, ipv6 = false)
        assertFalse(
            "client endpoints must not collapse to a shared reverse key",
            a.key() == b.key(),
        )
        val table = UdpClientEndpointTable(maxEntries = 8)
        assertTrue(table.noteActivity(a))
        assertTrue(table.noteActivity(b))
        assertTrue(table.contains(a))
        assertTrue(table.contains(b))
    }

    @Test
    fun socksUdpFraming_preservesArbitraryRemotePortNotOnlyDns() {
        val remote = InetAddress.getByName("104.16.0.1")
        val framed = Socks5UdpFraming.wrap(remote, 443, byteArrayOf(0x01))
        val parsed = Socks5UdpFraming.unwrap(framed)!!
        assertTrue(parsed.remotePort == 443)
        assertTrue(parsed.remote == remote)
    }
}
