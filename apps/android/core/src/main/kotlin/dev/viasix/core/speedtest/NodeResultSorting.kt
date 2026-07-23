package dev.viasix.core.speedtest

import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

/**
 * Sort keys for CFST result rows — aligned with macOS [NodeResultSortField]
 * and Windows [NodeSortKey].
 */
enum class NodeSortKey {
    LATENCY,
    LOSS,
    SPEED,
    IP,
    REGION,
    SENT,
    RECEIVED,
}

/**
 * Pure sorting for speed-test results.
 *
 * Numeric missing/non-finite values always sort last (both directions),
 * matching macOS [NodeResultSortComparator] so incomplete rows never displace
 * useful measurements.
 */
object NodeResultSorting {
    fun sorted(
        results: List<SpeedTestResult>,
        key: NodeSortKey,
        ascending: Boolean = true,
    ): List<SpeedTestResult> {
        if (results.size <= 1) return results
        return results
            .withIndex()
            .sortedWith { a, b ->
                val cmp = compare(a.value, b.value, key, ascending)
                if (cmp != 0) cmp else a.index.compareTo(b.index)
            }
            .map { it.value }
    }

    private fun compare(
        lhs: SpeedTestResult,
        rhs: SpeedTestResult,
        key: NodeSortKey,
        ascending: Boolean,
    ): Int =
        when (key) {
            NodeSortKey.LATENCY -> compareNumeric(lhs.latency, rhs.latency, ascending)
            NodeSortKey.LOSS -> compareNumeric(lhs.loss, rhs.loss, ascending)
            NodeSortKey.SPEED -> compareNumeric(lhs.speed, rhs.speed, ascending)
            NodeSortKey.SENT -> compareNumeric(lhs.sent, rhs.sent, ascending)
            NodeSortKey.RECEIVED -> compareNumeric(lhs.received, rhs.received, ascending)
            NodeSortKey.REGION -> compareText(lhs.region, rhs.region, ascending)
            NodeSortKey.IP -> compareIp(lhs.ip, rhs.ip, ascending)
        }

    /** Empty / unparsable → null so they pin to the bottom. */
    fun parseMetricNumber(raw: String): Double? {
        val m =
            Regex("""-?\d+(?:\.\d+)?""")
                .find(raw.replace(",", "").trim())
                ?: return null
        val value = m.value.toDoubleOrNull() ?: return null
        return if (value.isFinite()) value else null
    }

    private fun compareNumeric(lhs: String, rhs: String, ascending: Boolean): Int =
        compareOptional(parseMetricNumber(lhs), parseMetricNumber(rhs), ascending)

    private fun compareText(lhs: String, rhs: String, ascending: Boolean): Int {
        val a = lhs.trim()
        val b = rhs.trim()
        return compareOptional(
            a.ifEmpty { null },
            b.ifEmpty { null },
            ascending,
        ) { x, y -> x.compareTo(y, ignoreCase = true) }
    }

    private fun compareIp(lhs: String, rhs: String, ascending: Boolean): Int =
        compareOptional(ipSortKey(lhs), ipSortKey(rhs), ascending) { a, b ->
            val family = a.familyRank.compareTo(b.familyRank)
            if (family != 0) return@compareOptional family
            val len = minOf(a.bytes.size, b.bytes.size)
            for (i in 0 until len) {
                val c = (a.bytes[i].toInt() and 0xff).compareTo(b.bytes[i].toInt() and 0xff)
                if (c != 0) return@compareOptional c
            }
            a.bytes.size.compareTo(b.bytes.size)
        }

    private fun ipSortKey(value: String): IpSortKey? {
        val raw = value.trim()
        if (raw.isEmpty()) return null
        return try {
            when (val addr = InetAddress.getByName(raw)) {
                is Inet4Address -> IpSortKey(0, addr.address)
                is Inet6Address -> IpSortKey(1, addr.address)
                else -> null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun <T : Comparable<T>> compareOptional(
        lhs: T?,
        rhs: T?,
        ascending: Boolean,
    ): Int = compareOptional(lhs, rhs, ascending) { a, b -> a.compareTo(b) }

    /**
     * Missing values always sort last in **both** directions (macOS semantics);
     * only present pairs honor [ascending].
     */
    private fun <T> compareOptional(
        lhs: T?,
        rhs: T?,
        ascending: Boolean,
        using: (T, T) -> Int,
    ): Int =
        when {
            lhs == null && rhs == null -> 0
            lhs == null -> 1 // missing last (not reversed)
            rhs == null -> -1
            else -> {
                val cmp = using(lhs, rhs)
                if (ascending) cmp else -cmp
            }
        }

    private data class IpSortKey(val familyRank: Int, val bytes: ByteArray)
}
