package dev.viasix.app.ui

import dev.viasix.core.projection.RoutingMode

/**
 * Presentation metadata for routing modes, aligned with macOS
 * [ProxyRoutingMode] copy so users see consistent wording across platforms.
 */
fun RoutingMode.displayName(): String =
    when (this) {
        RoutingMode.RULE -> "规则"
        RoutingMode.GLOBAL -> "全局"
        RoutingMode.DIRECT -> "直连"
    }

fun RoutingMode.description(): String =
    when (this) {
        RoutingMode.RULE -> "私有地址直连，其余流量通过代理。"
        RoutingMode.GLOBAL -> "所有经过本地代理的流量都通过代理节点。"
        RoutingMode.DIRECT -> "所有经过本地代理的流量都直接连接。"
    }
