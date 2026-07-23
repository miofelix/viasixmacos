package dev.viasix.app.session

import dev.viasix.core.net.Ipv6Address

enum class DnsRoutingMode(
    val wire: String,
    val label: String,
    val detail: String,
) {
    PROXY(
        wire = "proxy",
        label = "经代理",
        detail = "DNS 查询通过 mihomo SOCKS 转发，避免全量隧道中的固定直连泄漏。",
    ),
    DIRECT(
        wire = "direct",
        label = "直连",
        detail = "DNS 查询使用受保护的系统外直连套接字，不进入 VPN。",
    ),
    ;

    companion object {
        fun parse(wire: String?): DnsRoutingMode =
            entries.firstOrNull { it.wire == wire } ?: PROXY
    }
}

data class DnsSettingsState(
    val mode: DnsRoutingMode = DnsRoutingMode.PROXY,
    val server: String = DnsSettingsPolicy.DEFAULT_SERVER,
) {
    val normalizedServer: String?
        get() = DnsSettingsPolicy.normalizeServer(server)
}

object DnsSettingsPolicy {
    const val DEFAULT_SERVER = "1.1.1.1"

    fun normalizeServer(value: String): String? {
        val input = value.trim()
        if (input.isEmpty()) return null
        if (':' in input) return Ipv6Address.normalize(input)
        val parts = input.split('.')
        if (parts.size != 4) return null
        val numbers =
            parts.map { part ->
                if (part.isEmpty() || part.length > 3 || part.any { !it.isDigit() }) return null
                part.toIntOrNull()?.takeIf { it in 0..255 } ?: return null
            }
        return numbers.joinToString(".")
    }

    fun isValidServer(value: String): Boolean = normalizeServer(value) != null

    fun shouldUseProtectedDirect(
        destinationPort: Int,
        mode: DnsRoutingMode,
    ): Boolean = destinationPort == 53 && mode == DnsRoutingMode.DIRECT
}
