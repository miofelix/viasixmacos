package dev.viasix.app.tun

import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

/**
 * Simple UDP NAT for the userspace forwarder.
 *
 * Outbound observes (client → remote); inbound resolves remote source back to the
 * last client that sent to that remote endpoint (standard single-device NAT).
 * Entries expire after [idleTimeoutMs] without activity.
 */
internal class UdpNatTable(
    private val maxEntries: Int = 256,
    private val idleTimeoutMs: Long = 60_000L,
    private val clock: () -> Long = { System.currentTimeMillis() },
) {
    data class ClientEndpoint(
        val ip: InetAddress,
        val port: Int,
        /** true when the original packet was IPv6 (reply must use IPv6 headers). */
        val ipv6: Boolean = false,
    )

    data class RemoteEndpoint(
        val ip: InetAddress,
        val port: Int,
    )

    private data class Entry(
        val client: ClientEndpoint,
        val remote: RemoteEndpoint,
        @Volatile var lastSeenMs: Long,
    )

    /** reverse: remote host:port → entry */
    private val byRemote = ConcurrentHashMap<String, Entry>()

    /** forward: client host:port|remote host:port → entry (for refresh / limits) */
    private val byFlow = ConcurrentHashMap<String, Entry>()

    val size: Int
        get() = byFlow.size

    /**
     * Record an outbound datagram. Returns false if the table is full and this is a new flow.
     */
    fun observeOutbound(
        clientIp: InetAddress,
        clientPort: Int,
        remoteIp: InetAddress,
        remotePort: Int,
        ipv6: Boolean = false,
    ): Boolean {
        purgeExpired()
        val flowKey = flowKey(clientIp, clientPort, remoteIp, remotePort)
        val existing = byFlow[flowKey]
        val now = clock()
        if (existing != null) {
            existing.lastSeenMs = now
            byRemote[remoteKey(remoteIp, remotePort)] = existing
            return true
        }
        if (byFlow.size >= maxEntries) return false
        val entry =
            Entry(
                client = ClientEndpoint(clientIp, clientPort, ipv6),
                remote = RemoteEndpoint(remoteIp, remotePort),
                lastSeenMs = now,
            )
        byFlow[flowKey] = entry
        byRemote[remoteKey(remoteIp, remotePort)] = entry
        return true
    }

    fun lookupInbound(remoteIp: InetAddress, remotePort: Int): ClientEndpoint? {
        purgeExpired()
        val entry = byRemote[remoteKey(remoteIp, remotePort)] ?: return null
        entry.lastSeenMs = clock()
        return entry.client
    }

    fun clear() {
        byFlow.clear()
        byRemote.clear()
    }

    fun purgeExpired() {
        val now = clock()
        val expiredFlows = byFlow.entries.filter { now - it.value.lastSeenMs > idleTimeoutMs }
        for (e in expiredFlows) {
            byFlow.remove(e.key, e.value)
            val rk = remoteKey(e.value.remote.ip, e.value.remote.port)
            byRemote.remove(rk, e.value)
        }
    }

    private fun flowKey(
        clientIp: InetAddress,
        clientPort: Int,
        remoteIp: InetAddress,
        remotePort: Int,
    ): String =
        "${clientIp.hostAddress}:$clientPort>${remoteIp.hostAddress}:$remotePort"

    private fun remoteKey(remoteIp: InetAddress, remotePort: Int): String =
        "${remoteIp.hostAddress}:$remotePort"
}
