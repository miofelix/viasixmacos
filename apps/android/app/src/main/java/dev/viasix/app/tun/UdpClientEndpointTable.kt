package dev.viasix.app.tun

import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

/**
 * Tracks local UDP client endpoints that own a SOCKS5 UDP ASSOCIATE.
 *
 * Demux is **per client (ip, port)**, not per remote: each client endpoint gets its own
 * associate socket so concurrent flows to the same remote (e.g. two QUIC to CDN:443)
 * cannot steal each other's replies. Proxied DNS uses the same per-client isolation.
 */
internal class UdpClientEndpointTable(
    private val maxEntries: Int = 256,
    private val idleTimeoutMs: Long = 60_000L,
    private val clock: () -> Long = { System.nanoTime() / 1_000_000L },
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
    @Synchronized
    fun noteActivity(endpoint: Endpoint): Boolean {
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

    @Synchronized
    fun contains(endpoint: Endpoint): Boolean {
        return byClient.containsKey(endpoint.key())
    }

    @Synchronized
    fun remove(endpoint: Endpoint) {
        byClient.remove(endpoint.key())
    }

    @Synchronized
    fun clear() {
        byClient.clear()
    }

    /**
     * Remove idle endpoints and return those dropped. [onExpired] runs while registration
     * is locked so a newly active endpoint cannot be confused with the generation being reaped.
     */
    @Synchronized
    fun purgeExpired(onExpired: (Endpoint) -> Unit = {}): List<Endpoint> {
        val now = clock()
        val dropped = mutableListOf<Endpoint>()
        for (e in byClient.entries.toList()) {
            if (now - e.value.lastSeenMs > idleTimeoutMs) {
                if (byClient.remove(e.key, e.value)) {
                    dropped += e.value.endpoint
                    onExpired(e.value.endpoint)
                }
            }
        }
        return dropped
    }

    @Synchronized
    fun endpoints(): List<Endpoint> = byClient.values.map { it.endpoint }
}
