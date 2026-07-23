package dev.viasix.app.session

import dev.viasix.core.net.Ipv6Address
import dev.viasix.core.profile.ProfileSummary
import dev.viasix.core.profile.ProfileSummaryParser
import dev.viasix.core.projection.RoutingMode

/**
 * Pure start-session validation shared by MainActivity and the Quick Settings tile.
 * Semantics match macOS “cannot start without node/config” gates (direct is exempt).
 */
object SessionStartGate {
    sealed class Result {
        data object Ok : Result()

        data class Blocked(
            val message: String,
            /** Suggested UI section: "nodes" | "profiles" | "settings" | null */
            val sectionWire: String? = null,
        ) : Result()
    }

    fun evaluate(
        routingMode: RoutingMode,
        selectedAddress: String,
        profileYaml: String,
        appRoutingMode: AppRoutingMode = AppRoutingMode.ALL,
        selectedAppPackages: Collection<String> = emptyList(),
        dnsServer: String = DnsSettingsPolicy.DEFAULT_SERVER,
        fullTunnel: Boolean = true,
        vpnMtu: String = VpnMtuPolicy.DEFAULT.toString(),
        ipv6RoutingMode: Ipv6RoutingMode = Ipv6RoutingMode.TUNNEL,
    ): Result {
        val summary = ProfileSummaryParser.parse(profileYaml)
        return evaluate(
            routingMode,
            selectedAddress,
            summary,
            appRoutingMode,
            selectedAppPackages,
            dnsServer,
            fullTunnel,
            vpnMtu,
            ipv6RoutingMode,
        )
    }

    fun evaluate(
        routingMode: RoutingMode,
        selectedAddress: String,
        summary: ProfileSummary,
        appRoutingMode: AppRoutingMode = AppRoutingMode.ALL,
        selectedAppPackages: Collection<String> = emptyList(),
        dnsServer: String = DnsSettingsPolicy.DEFAULT_SERVER,
        fullTunnel: Boolean = true,
        vpnMtu: String = VpnMtuPolicy.DEFAULT.toString(),
        ipv6RoutingMode: Ipv6RoutingMode = Ipv6RoutingMode.TUNNEL,
    ): Result {
        if (!VpnMtuPolicy.isValid(vpnMtu)) {
            return Result.Blocked(
                message = "无法连接：VPN MTU 必须在 ${VpnMtuPolicy.MIN}–${VpnMtuPolicy.MAX} 之间",
                sectionWire = "settings",
            )
        }
        if (fullTunnel && !DnsSettingsPolicy.isValidServer(dnsServer)) {
            return Result.Blocked(
                message = "无法连接：请输入合法的 IPv4 或 IPv6 DNS 地址",
                sectionWire = "settings",
            )
        }
        if (
            fullTunnel &&
                ipv6RoutingMode != Ipv6RoutingMode.TUNNEL &&
                ':' in (DnsSettingsPolicy.normalizeServer(dnsServer) ?: "")
        ) {
            return Result.Blocked(
                message = "无法连接：${ipv6RoutingMode.label} IPv6 模式需要使用 IPv4 DNS",
                sectionWire = "settings",
            )
        }
        if (
            appRoutingMode == AppRoutingMode.ONLY_SELECTED &&
                selectedAppPackages.none(AppRoutingPolicy::isValidPackageName)
        ) {
            return Result.Blocked(
                message = "无法连接：仅代理所选应用模式至少需要选择一个应用",
                sectionWire = "settings",
            )
        }
        if (routingMode == RoutingMode.DIRECT) return Result.Ok

        val normalized = Ipv6Address.normalize(selectedAddress)
        if (normalized == null || !Ipv6Address.isValid(normalized)) {
            return Result.Blocked(
                message = "无法连接：请先选择合法 IPv6 节点",
                sectionWire = "nodes",
            )
        }
        if (summary.primary == null) {
            return Result.Blocked(
                message = "无法连接：连接配置缺少有效代理入口",
                sectionWire = "profiles",
            )
        }
        return Result.Ok
    }
}
