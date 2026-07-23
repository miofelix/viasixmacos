package dev.viasix.app.tun

import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks local UDP client endpoints that own a SOCKS5 UDP ASSOCIATE.
 *
 * Demux is **per client (ip, port)**, not per remote: each client endpoint gets its own
 * associate socket so concurrent flows to the same remote (e.g. two QUIC to CDN:443)
 * cannot steal each other's replies. DNS (port 53) does not use this table.
 */
internal class UdpClientEndpointTable(
    private val maxEntries: Int = 256,
    private val idleTimeoutMs: Long = 60_000L,
    private val clock: () -> Long = { System.currentTimeMillis() },
) {
    data class Endpoint(
        val ip: InetAddress,
        val port: Int,
        val ipv6: Boolean = false,
    ) {
        fun key(): String = "${ip.hostAddress}:$port:${if (ipv6) "6" else "4"}"
    }

    private data class Entry(
        val endpoint: Endpoint,
        @Volatile var lastSeenMs: Long,
    )

    private val byClient = ConcurrentHashMap<String, Entry>()

    val size: Int
        get() = byClient.size

    /**
     * Record activity for a client endpoint. Returns false if the table is full and
     * this client is not already registered.
     */
    fun noteActivity(endpoint: Endpoint): Boolean {
        purgeExpired()
        val key = endpoint.key()
        val existing = byClient[key]
        val now = clock()
        if (existing != null) {
            existing.lastSeenMs = now
            return true
        }
        if (byClient.size >= maxEntries) return false
        byClient[key] = Entry(endpoint, now)
        return true
    }

    fun contains(endpoint: Endpoint): Boolean {
        purgeExpired()
        return byClient.containsKey(endpoint.key())
    }

    fun remove(endpoint: Endpoint) {
        byClient.remove(endpoint.key())
    }

    fun clear() {
        byClient.clear()
    }

    /** Remove idle endpoints; returns the endpoints that were dropped. */
    fun purgeExpired(): List<Endpoint> {
        val now = clock()
        val dropped = mutableListOf<Endpoint>()
        for (e in byClient.entries.toList()) {
            if (now - e.value.lastSeenMs > idleTimeoutMs) {
                if (byClient.remove(e.key, e.value)) {
                    dropped += e.value.endpoint
                }
            }
        }
        return dropped
    }

    fun endpoints(): List<Endpoint> = byClient.values.map { it.endpoint }
}
