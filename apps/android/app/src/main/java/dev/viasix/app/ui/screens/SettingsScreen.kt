package dev.viasix.app.ui.screens

import android.os.Build
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Route
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import dev.viasix.app.BuildConfig
import dev.viasix.app.net.ExitIPDetectionMode
import dev.viasix.app.net.ExitIPDetector
import dev.viasix.app.runtime.RuntimeComponentCondition
import dev.viasix.app.runtime.RuntimeComponentId
import dev.viasix.app.runtime.RuntimeComponentInfo
import dev.viasix.app.session.AppRoutingMode
import dev.viasix.app.session.AppRoutingPolicy
import dev.viasix.app.session.DnsRoutingMode
import dev.viasix.app.session.DnsSettingsPolicy
import dev.viasix.app.session.Ipv6RoutingMode
import dev.viasix.app.session.VpnMtuPolicy
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.ui.AppSection
import dev.viasix.app.ui.displayName
import dev.viasix.app.ui.theme.AppPageHeader
import dev.viasix.app.ui.theme.AppTone
import dev.viasix.app.ui.theme.CardHeader
import dev.viasix.app.ui.theme.CompactInfoRow
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.SettingRow
import dev.viasix.app.ui.theme.SurfaceCard
import dev.viasix.app.ui.theme.VisualStyle

@Composable
fun SettingsScreen(
    state: SessionUiState,
    onFullTunnelChange: (Boolean) -> Unit,
    onExitIpModeChange: (ExitIPDetectionMode) -> Unit,
    onExitIpEndpointChange: (String) -> Unit,
    onDetectExitIp: () -> Unit,
    onClearSessionData: () -> Unit,
    onInspectRuntimeComponents: () -> Unit = {},
    onRepairRuntimeComponent: (RuntimeComponentId) -> Unit = {},
    onManageNotificationPermission: () -> Unit = {},
    onManageVpnPermission: () -> Unit = {},
    onManageBatteryOptimization: () -> Unit = {},
    onAppRoutingModeChange: (AppRoutingMode) -> Unit = {},
    onToggleAppRoutingPackage: (String) -> Unit = {},
    onClearSelectedAppPackages: () -> Unit = {},
    onRefreshInstalledApps: () -> Unit = {},
    onDnsRoutingModeChange: (DnsRoutingMode) -> Unit = {},
    onDnsServerChange: (String) -> Unit = {},
    onVpnMtuChange: (String) -> Unit = {},
    onVpnMeteredChange: (Boolean) -> Unit = {},
    onBypassLocalNetworkChange: (Boolean) -> Unit = {},
    onIpv6RoutingModeChange: (Ipv6RoutingMode) -> Unit = {},
) {
    val colors = LocalViaSixColors.current
    val uriHandler = LocalUriHandler.current
    val tunnelLocked = state.connectionPhase.isActiveOrTransitioning
    var showAppPicker by remember { mutableStateOf(false) }
    var appSearch by remember { mutableStateOf("") }
    var manualPackage by remember { mutableStateOf("") }

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.SETTINGS.title,
            subtitle = AppSection.SETTINGS.subtitle,
        )

        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(
                        horizontal = VisualStyle.pageHorizontalPadding,
                        vertical = VisualStyle.pageVerticalPadding,
                    ),
            verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
        ) {
            SurfaceCard {
                CardHeader(title = "网络接入", icon = Icons.Outlined.VpnKey, tone = AppTone.Accent)
                HorizontalDivider(color = colors.surfaceBorder)
                SettingRow(
                    title = "全量隧道",
                    detail = "默认路由 + 用户态 TCP/UDP（IPv4/IPv6→SOCKS；DNS 可经代理或直连）",
                    icon = Icons.Outlined.VpnKey,
                ) {
                    Switch(
                        checked = state.fullTunnel,
                        onCheckedChange = onFullTunnelChange,
                        enabled = !tunnelLocked,
                    )
                }
                Text(
                    text =
                        "关闭后仅建立带 HTTP 代理元数据的 VPN 会话（无默认路由），" +
                            "依赖应用自身代理感知。Android 无系统级 HTTP/SOCKS 代理开关。" +
                            if (tunnelLocked) {
                                "运行中不可切换，请先断开。"
                            } else {
                                "变更在下次连接时生效。"
                            },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder)
                OutlinedTextField(
                    value = state.vpnMtu,
                    onValueChange = onVpnMtuChange,
                    label = { Text("VPN MTU") },
                    isError = !VpnMtuPolicy.isValid(state.vpnMtu),
                    enabled = !tunnelLocked,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(
                                start = VisualStyle.spacing16,
                                end = VisualStyle.spacing16,
                                top = VisualStyle.spacing12,
                            ),
                )
                Text(
                    text =
                        if (VpnMtuPolicy.isValid(state.vpnMtu)) {
                            "允许 ${VpnMtuPolicy.MIN}–${VpnMtuPolicy.MAX}，默认 ${VpnMtuPolicy.DEFAULT}；变更在下次连接时生效。"
                        } else {
                            "请输入 ${VpnMtuPolicy.MIN}–${VpnMtuPolicy.MAX} 之间的整数。"
                        },
                    style = MaterialTheme.typography.bodySmall,
                    color =
                        if (VpnMtuPolicy.isValid(state.vpnMtu)) {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        } else {
                            colors.warning
                        },
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder)
                SettingRow(
                    title = "按流量计费 VPN",
                    detail =
                        when {
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ->
                                "Android 10+ 可配置；当前系统由平台决定"
                            state.vpnMetered -> "保持 Android 默认计费属性"
                            else -> "标记为不计费，减少后台数据限制"
                        },
                    icon = Icons.Outlined.VpnKey,
                ) {
                    Switch(
                        checked = state.vpnMetered,
                        onCheckedChange = onVpnMeteredChange,
                        enabled =
                            !tunnelLocked &&
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q,
                    )
                }
                Text(
                    text =
                        when {
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ->
                                "此系统版本不支持设置 VPN 计费属性。"
                            state.vpnMetered ->
                                "系统可在节省流量模式下限制经 VPN 的后台数据；这是兼容当前行为的默认值。"
                            else ->
                                "仅改变 Android 对 VPN 的策略分类，不会改变蜂窝网络套餐或实际资费。"
                        } +
                            if (tunnelLocked) {
                                " 运行中不可修改，请先断开。"
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                " 变更在下次连接时生效。"
                            } else {
                                ""
                            },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder)
                SettingRow(
                    title = "绕过局域网",
                    detail =
                        when {
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ->
                                "Android 13+ 可用"
                            !state.fullTunnel -> "仅全量隧道使用"
                            state.bypassLocalNetwork -> "私网、链路本地与组播流量直连"
                            else -> "局域网流量与其他流量一同进入 VPN"
                        },
                    icon = Icons.Outlined.Route,
                ) {
                    Switch(
                        checked = state.bypassLocalNetwork,
                        onCheckedChange = onBypassLocalNetworkChange,
                        enabled =
                            !tunnelLocked &&
                                state.fullTunnel &&
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
                    )
                }
                Text(
                    text =
                        when {
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ->
                                "此系统版本不支持原生 VPN 路由排除。"
                            !state.fullTunnel ->
                                "开启全量隧道后可配置；当前 HTTP 代理 VPN 没有默认路由。"
                            state.bypassLocalNetwork ->
                                "便于访问路由器、NAS 和局域网发现；系统锁定 VPN 仍可能阻止隧道外流量。"
                            else ->
                                "默认保持所有目标随 VPN 路由，以减少意外绕过。"
                        } +
                            if (tunnelLocked) {
                                " 运行中不可修改，请先断开。"
                            } else if (
                                state.fullTunnel &&
                                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                            ) {
                                " 变更在下次连接时生效。"
                            } else {
                                ""
                            },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("IPv6 应用流量", state.ipv6RoutingMode.label)
                Row(
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = VisualStyle.spacing16),
                    horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                ) {
                    Ipv6RoutingMode.entries.forEach { mode ->
                        if (state.ipv6RoutingMode == mode) {
                            FilledTonalButton(
                                onClick = { onIpv6RoutingModeChange(mode) },
                                enabled = !tunnelLocked && state.fullTunnel,
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(mode.label)
                            }
                        } else {
                            OutlinedButton(
                                onClick = { onIpv6RoutingModeChange(mode) },
                                enabled = !tunnelLocked && state.fullTunnel,
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(mode.label)
                            }
                        }
                    }
                }
                val ipv6DnsIncompatible =
                    state.fullTunnel &&
                        state.ipv6RoutingMode != Ipv6RoutingMode.TUNNEL &&
                        (DnsSettingsPolicy.normalizeServer(state.dnsSettings.server) ?: "")
                            .contains(':')
                Text(
                    text =
                        when {
                            !state.fullTunnel -> "仅全量隧道使用此设置。"
                            ipv6DnsIncompatible ->
                                "当前模式不会让 IPv6 DNS 进入 VPN，请改用数字 IPv4 DNS。"
                            else -> state.ipv6RoutingMode.detail
                        } +
                            if (tunnelLocked) {
                                " 运行中不可修改，请先断开。"
                            } else if (state.fullTunnel) {
                                " 变更在下次连接时生效。"
                            } else {
                                ""
                            },
                    style = MaterialTheme.typography.bodySmall,
                    color =
                        if (ipv6DnsIncompatible || state.ipv6RoutingMode == Ipv6RoutingMode.BYPASS) {
                            colors.warning
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("DNS 路由", state.dnsSettings.mode.label)
                Row(
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = VisualStyle.spacing16),
                    horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                ) {
                    DnsRoutingMode.entries.forEach { mode ->
                        if (state.dnsSettings.mode == mode) {
                            FilledTonalButton(
                                onClick = { onDnsRoutingModeChange(mode) },
                                enabled = !tunnelLocked,
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(mode.label)
                            }
                        } else {
                            OutlinedButton(
                                onClick = { onDnsRoutingModeChange(mode) },
                                enabled = !tunnelLocked,
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(mode.label)
                            }
                        }
                    }
                }
                OutlinedTextField(
                    value = state.dnsSettings.server,
                    onValueChange = onDnsServerChange,
                    label = { Text("DNS 服务器（数字 IP）") },
                    isError = !DnsSettingsPolicy.isValidServer(state.dnsSettings.server),
                    enabled = !tunnelLocked,
                    singleLine = true,
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(
                                start = VisualStyle.spacing16,
                                end = VisualStyle.spacing16,
                                top = VisualStyle.spacing8,
                            ),
                )
                Text(
                    text =
                        if (DnsSettingsPolicy.isValidServer(state.dnsSettings.server)) {
                            state.dnsSettings.mode.detail + " 仅全量隧道使用此设置。"
                        } else {
                            "请输入合法的数字 IPv4 或 IPv6 地址。"
                        },
                    style = MaterialTheme.typography.bodySmall,
                    color =
                        if (DnsSettingsPolicy.isValidServer(state.dnsSettings.server)) {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        } else {
                            colors.warning
                        },
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("VPN 权限", state.vpnPermission.statusLabel)
                Text(
                    text =
                        if (state.vpnPermission.granted) {
                            "系统已允许 ViaSix 建立 VPN；可继续配置“始终开启 VPN”等系统选项。"
                        } else {
                            "连接前必须由系统授权 ViaSix 建立 VPN；可在此预先完成授权。"
                        },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing8,
                        ),
                )
                OutlinedButton(
                    onClick = onManageVpnPermission,
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(
                                start = VisualStyle.spacing16,
                                end = VisualStyle.spacing16,
                                bottom = VisualStyle.spacing12,
                            ),
                ) {
                    Text(state.vpnPermission.actionLabel)
                }
            }

            SurfaceCard {
                val appRouting = state.appRouting
                CardHeader(
                    title = "分应用路由",
                    icon = Icons.Outlined.Apps,
                    tone = AppTone.Accent,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                ) {
                    AppRoutingMode.entries.forEach { mode ->
                        if (appRouting.mode == mode) {
                            FilledTonalButton(
                                onClick = { onAppRoutingModeChange(mode) },
                                enabled = !tunnelLocked,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(mode.label)
                            }
                        } else {
                            OutlinedButton(
                                onClick = { onAppRoutingModeChange(mode) },
                                enabled = !tunnelLocked,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(mode.label)
                            }
                        }
                    }
                    Text(
                        text = appRouting.mode.detail,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (
                        appRouting.mode == AppRoutingMode.ONLY_SELECTED &&
                            appRouting.selectedPackages.isEmpty()
                    ) {
                        Text(
                            text = "至少选择一个应用后才能连接。",
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.warning,
                        )
                    }
                    CompactInfoRow("已选择", "${appRouting.selectedCount} 个应用")
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                    ) {
                        OutlinedButton(
                            onClick = {
                                showAppPicker = true
                                if (appRouting.installedApps.isEmpty()) onRefreshInstalledApps()
                            },
                            enabled = !tunnelLocked,
                            modifier = Modifier.weight(1f),
                        ) {
                            Text("选择应用")
                        }
                        TextButton(
                            onClick = onClearSelectedAppPackages,
                            enabled = !tunnelLocked && appRouting.selectedPackages.isNotEmpty(),
                        ) {
                            Text("清空")
                        }
                    }
                    if (tunnelLocked) {
                        Text(
                            text = "运行中不可修改应用路由，请先断开 VPN。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            SurfaceCard {
                val notification = state.notificationPermission
                val notificationTone =
                    if (notification.granted) AppTone.Positive else AppTone.Warning
                CardHeader(
                    title = "会话通知",
                    icon =
                        if (notification.granted) {
                            Icons.Outlined.NotificationsActive
                        } else {
                            Icons.Outlined.NotificationsOff
                        },
                    tone = notificationTone,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("权限", notification.statusLabel)
                Text(
                    text =
                        if (notification.granted) {
                            "连接时显示实时上下行、连接数和一键断开控制。"
                        } else {
                            "VPN 仍可运行，但实时速率和通知断开按钮可能不会显示。"
                        },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom =
                                if (notification.required && !notification.granted) {
                                    VisualStyle.spacing8
                                } else {
                                    VisualStyle.spacing16
                                },
                        ),
                )
                if (notification.required && !notification.granted) {
                    OutlinedButton(
                        onClick = onManageNotificationPermission,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .padding(
                                    start = VisualStyle.spacing16,
                                    end = VisualStyle.spacing16,
                                    bottom = VisualStyle.spacing12,
                                ),
                    ) {
                        Text(
                            if (notification.canRequestInApp) {
                                "允许会话通知"
                            } else {
                                "打开系统通知设置"
                            },
                        )
                    }
                }
            }

            SurfaceCard {
                val battery = state.batteryOptimization
                CardHeader(
                    title = "后台运行",
                    icon = Icons.Outlined.Settings,
                    tone = if (battery.exempt) AppTone.Positive else AppTone.Warning,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("电池优化", battery.statusLabel)
                Text(
                    text =
                        if (battery.exempt) {
                            "ViaSix 不受系统电池优化限制，更适合长期连接和始终开启 VPN。"
                        } else {
                            "部分设备可能在后台回收前台 VPN；如需长期连接，可在系统中将 ViaSix 设为不受限制。"
                        },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing8,
                        ),
                )
                OutlinedButton(
                    onClick = onManageBatteryOptimization,
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .padding(
                                start = VisualStyle.spacing16,
                                end = VisualStyle.spacing16,
                                bottom = VisualStyle.spacing12,
                            ),
                ) {
                    Text("打开电池优化设置")
                }
            }

            SurfaceCard {
                CardHeader(title = "出口 IP 检测", icon = Icons.Outlined.Public, tone = AppTone.Accent)
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        ExitIPDetectionMode.entries.forEach { mode ->
                            val selected = state.exitIP.mode == mode
                            FilledTonalButton(
                                onClick = { onExitIpModeChange(mode) },
                                modifier = Modifier.weight(1f).height(36.dp),
                                colors =
                                    if (selected) {
                                        ButtonDefaults.filledTonalButtonColors(
                                            containerColor = colors.accent.copy(alpha = 0.22f),
                                        )
                                    } else {
                                        ButtonDefaults.filledTonalButtonColors()
                                    },
                            ) { Text(mode.label) }
                        }
                    }
                    OutlinedTextField(
                        value = state.exitIP.endpoint,
                        onValueChange = onExitIpEndpointChange,
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text("自动模式端点") },
                        supportingText = {
                            Text("默认 ${ExitIPDetector.DEFAULT_ENDPOINT}；IPv4/IPv6 模式使用固定端点")
                        },
                    )
                    Button(
                        onClick = onDetectExitIp,
                        enabled = !state.exitIP.isDetecting,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (state.exitIP.isDetecting) "检测中…" else "立即检测")
                    }
                    state.exitIP.info?.let { info ->
                        Text(
                            buildString {
                                append(info.ip)
                                if (info.family.isNotBlank()) append(" · ${info.family}")
                                if (info.location.isNotBlank()) append("\n${info.location}")
                                if (info.details.isNotBlank()) append("\n${info.details}")
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    state.exitIP.errorMessage?.let { err ->
                        Text(err, color = colors.negative, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }

            SurfaceCard {
                val componentState = state.runtimeComponents
                val mihomoInfo =
                    if (state.runtime.running) {
                        componentState.mihomo.copy(
                            condition = RuntimeComponentCondition.READY,
                            detail =
                                "运行中" +
                                    (state.runtime.mihomoVersion?.let { " · $it" } ?: ""),
                        )
                    } else {
                        componentState.mihomo
                    }
                val cfstInfo =
                    if (state.speedTest.binaryReady &&
                        componentState.cfst.condition != RuntimeComponentCondition.INVALID
                    ) {
                        componentState.cfst.copy(
                            condition = RuntimeComponentCondition.READY,
                            detail = state.speedTest.message.ifBlank { componentState.cfst.detail },
                        )
                    } else {
                        componentState.cfst
                    }
                CardHeader(title = "运行组件", icon = Icons.Outlined.Settings, tone = AppTone.Neutral)
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow(
                    "内核 mihomo",
                    runtimeComponentStatusLabel(
                        mihomoInfo,
                        checking = componentState.isInspecting,
                        repairing = componentState.repairing == RuntimeComponentId.MIHOMO,
                    ),
                )
                Text(
                    mihomoInfo.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing8,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "CFST 测速",
                    runtimeComponentStatusLabel(
                        cfstInfo,
                        checking = componentState.isInspecting,
                        repairing = componentState.repairing == RuntimeComponentId.CFST,
                    ),
                )
                Text(
                    if (state.speedTest.isRunning) "测速运行中" else cfstInfo.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing8,
                        ),
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("混合端口", "127.0.0.1:${state.runtime.mixedPort}")
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("控制器", "127.0.0.1:${state.runtime.controllerPort}")
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("路由模式", state.routingMode.displayName())
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("健康", state.runtime.health.ifBlank { "—" })
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "会话",
                    if (state.runtime.running) {
                        state.runtime.startedAtMillis?.let { started ->
                            val text =
                                java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
                                    .format(java.util.Date(started))
                            "运行中 · 自 $text"
                        } ?: "运行中"
                    } else {
                        "已停止"
                    },
                )
                Column(
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                            top = VisualStyle.spacing8,
                        ),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                ) {
                    OutlinedButton(
                        onClick = onInspectRuntimeComponents,
                        enabled = !componentState.busy,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (componentState.isInspecting) "正在检查…" else "重新检查组件")
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        FilledTonalButton(
                            onClick = {
                                onRepairRuntimeComponent(RuntimeComponentId.MIHOMO)
                            },
                            enabled =
                                !componentState.busy &&
                                    !state.connectionPhase.isActiveOrTransitioning &&
                                    mihomoInfo.condition != RuntimeComponentCondition.UNSUPPORTED,
                            modifier = Modifier.weight(1f),
                        ) {
                            Text(
                                runtimeComponentRepairLabel(
                                    RuntimeComponentId.MIHOMO,
                                    mihomoInfo,
                                    componentState.repairing,
                                ),
                            )
                        }
                        FilledTonalButton(
                            onClick = {
                                onRepairRuntimeComponent(RuntimeComponentId.CFST)
                            },
                            enabled =
                                !componentState.busy &&
                                    !state.speedTest.isRunning &&
                                    cfstInfo.condition != RuntimeComponentCondition.UNSUPPORTED,
                            modifier = Modifier.weight(1f),
                        ) {
                            Text(
                                runtimeComponentRepairLabel(
                                    RuntimeComponentId.CFST,
                                    cfstInfo,
                                    componentState.repairing,
                                ),
                            )
                        }
                    }
                    Text(
                        text =
                            "检查会区分缺失、损坏、错误架构和执行权限；修复会从 APK assets " +
                                "原子替换对应 AArch64 ELF。mihomo 仅可在断开后修复，" +
                                "CFST 仅可在测速停止后修复。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            SurfaceCard {
                val resetLocked = state.connectionPhase.isActiveOrTransitioning
                CardHeader(title = "数据", icon = Icons.Outlined.DeleteForever, tone = AppTone.Warning)
                HorizontalDivider(color = colors.surfaceBorder)
                Column(modifier = Modifier.padding(VisualStyle.spacing16)) {
                    Text(
                        "清除本机会话偏好（配置 YAML、节点候选、分应用选择、出口检测设置）。" +
                            "不会卸载 mihomo 二进制或撤销 VPN 权限。" +
                            if (resetLocked) " 请先断开 VPN 后再重置。" else "",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(
                        onClick = onClearSessionData,
                        enabled = !resetLocked,
                        colors =
                            ButtonDefaults.buttonColors(
                                containerColor = colors.warning,
                            ),
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .padding(top = VisualStyle.spacing12),
                    ) {
                        Text("重置会话偏好")
                    }
                }
            }

            SurfaceCard {
                CardHeader(title = "关于 ViaSix", icon = Icons.Outlined.Info, tone = AppTone.Neutral)
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("版本", BuildConfig.VERSION_NAME)
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("平台", "Android · VpnService")
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("契约", "contracts/fixtures · 与桌面端对齐")
                TextButton(
                    onClick = { uriHandler.openUri("https://github.com/miofelix/viasix") },
                    modifier = Modifier.padding(horizontal = VisualStyle.spacing8),
                ) {
                    Text("打开 GitHub 仓库")
                }
            }
        }
    }

    if (showAppPicker) {
        val query = appSearch.trim()
        val visibleApps =
            remember(state.appRouting.installedApps, query) {
                state.appRouting.installedApps.filter { app ->
                    query.isEmpty() ||
                        app.label.contains(query, ignoreCase = true) ||
                        app.packageName.contains(query, ignoreCase = true)
                }
            }
        AlertDialog(
            onDismissRequest = { showAppPicker = false },
            title = { Text("选择应用") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing8)) {
                    OutlinedTextField(
                        value = appSearch,
                        onValueChange = { appSearch = it },
                        label = { Text("搜索名称或包名") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        OutlinedTextField(
                            value = manualPackage,
                            onValueChange = { manualPackage = it },
                            label = { Text("高级：手动包名") },
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                        )
                        Button(
                            onClick = {
                                val packageName = manualPackage.trim()
                                onToggleAppRoutingPackage(packageName)
                                appSearch = packageName
                                manualPackage = ""
                            },
                            enabled =
                                !tunnelLocked &&
                                    AppRoutingPolicy.isValidPackageName(manualPackage) &&
                                    !state.appRouting.selectedPackages.contains(
                                        manualPackage.trim(),
                                    ),
                        ) {
                            Text("添加")
                        }
                    }
                    if (
                        manualPackage.isNotBlank() &&
                            !AppRoutingPolicy.isValidPackageName(manualPackage)
                    ) {
                        Text(
                            "请输入类似 com.example.app 的 Android 包名。",
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.warning,
                        )
                    }
                    when {
                        state.appRouting.isLoadingApps ->
                            Row(
                                modifier =
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(VisualStyle.spacing16),
                                horizontalArrangement = Arrangement.Center,
                            ) {
                                CircularProgressIndicator()
                            }
                        visibleApps.isEmpty() ->
                            Text(
                                "没有匹配的可启动应用。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        else ->
                            LazyColumn(modifier = Modifier.height(360.dp)) {
                                items(
                                    items = visibleApps,
                                    key = { it.packageName },
                                ) { app ->
                                    val checked =
                                        state.appRouting.selectedPackages.contains(app.packageName)
                                    Row(
                                        modifier =
                                            Modifier
                                                .fillMaxWidth()
                                                .clickable(enabled = !tunnelLocked) {
                                                    onToggleAppRoutingPackage(app.packageName)
                                                }
                                                .padding(vertical = VisualStyle.spacing4),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Checkbox(
                                            checked = checked,
                                            onCheckedChange = {
                                                onToggleAppRoutingPackage(app.packageName)
                                            },
                                            enabled = !tunnelLocked,
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = app.label,
                                                style = MaterialTheme.typography.bodyMedium,
                                            )
                                            Text(
                                                text =
                                                    if (app.launchable) {
                                                        app.packageName
                                                    } else {
                                                        "${app.packageName} · 无启动器入口或已卸载"
                                                    },
                                                style = MaterialTheme.typography.bodySmall,
                                                color =
                                                    if (app.launchable) {
                                                        MaterialTheme.colorScheme.onSurfaceVariant
                                                    } else {
                                                        colors.warning
                                                    },
                                            )
                                        }
                                    }
                                }
                            }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showAppPicker = false }) {
                    Text("完成")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = onRefreshInstalledApps,
                    enabled = !state.appRouting.isLoadingApps,
                ) {
                    Text("刷新")
                }
            },
        )
    }
}

private fun runtimeComponentStatusLabel(
    info: RuntimeComponentInfo,
    checking: Boolean,
    repairing: Boolean,
): String =
    when {
        repairing -> "修复中"
        checking -> "检查中"
        else -> info.condition.label
    }

private fun runtimeComponentRepairLabel(
    component: RuntimeComponentId,
    info: RuntimeComponentInfo,
    repairing: RuntimeComponentId?,
): String {
    if (repairing == component) return "修复中…"
    val action =
        when (info.condition) {
            RuntimeComponentCondition.READY -> "重装"
            RuntimeComponentCondition.MISSING -> "安装"
            else -> "修复"
        }
    return "$action ${if (component == RuntimeComponentId.MIHOMO) "mihomo" else "CFST"}"
}
