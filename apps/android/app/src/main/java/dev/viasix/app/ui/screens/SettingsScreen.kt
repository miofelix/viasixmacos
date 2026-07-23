package dev.viasix.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import dev.viasix.app.BuildConfig
import dev.viasix.app.net.ExitIPDetectionMode
import dev.viasix.app.net.ExitIPDetector
import dev.viasix.app.runtime.RuntimeComponentCondition
import dev.viasix.app.runtime.RuntimeComponentId
import dev.viasix.app.runtime.RuntimeComponentInfo
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
) {
    val colors = LocalViaSixColors.current
    val uriHandler = LocalUriHandler.current
    val tunnelLocked = state.connectionPhase.isActiveOrTransitioning

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
                    detail = "默认路由 + 用户态 TCP/UDP（IPv4/IPv6→SOCKS；DNS 独立 protect）",
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
                        "清除本机会话偏好（配置 YAML、节点候选、出口检测设置）。" +
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
