package dev.viasix.app.session

enum class Ipv6RoutingMode(
    val wire: String,
    val label: String,
    val detail: String,
) {
    TUNNEL(
        wire = "tunnel",
        label = "经 VPN",
        detail = "IPv6 应用流量进入 ViaSix；默认路由无法建立时中止连接，避免旁路。",
    ),
    BLOCK(
        wire = "block",
        label = "阻止",
        detail = "阻止应用 IPv6 流量离开 VPN；mihomo 仍可使用所选 IPv6 代理入口。",
    ),
    BYPASS(
        wire = "bypass",
        label = "绕过 VPN",
        detail = "明确允许应用 IPv6 直连物理网络，可能暴露真实 IPv6 地址。",
    ),
    ;

    companion object {
        fun parse(wire: String?): Ipv6RoutingMode =
            entries.firstOrNull { it.wire == wire } ?: TUNNEL
    }
}
