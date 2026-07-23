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
import dev.viasix.app.net.ExitIPDetectionMode
import dev.viasix.app.net.ExitIPDetector
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
    onRefreshCfstStatus: () -> Unit = {},
) {
    val colors = LocalViaSixColors.current
    val uriHandler = LocalUriHandler.current

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
                    )
                }
                Text(
                    text =
                        "关闭后仅建立带 HTTP 代理元数据的 VPN 会话（无默认路由），" +
                            "依赖应用自身代理感知。Android 无系统级 HTTP/SOCKS 代理开关。" +
                            "变更后需重新连接生效。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                        ),
                )
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
                CardHeader(title = "运行组件", icon = Icons.Outlined.Settings, tone = AppTone.Neutral)
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("内核", state.runtime.mihomoVersion ?: "mihomo（assets → filesDir）")
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "CFST",
                    when {
                        state.speedTest.isRunning -> "测速运行中"
                        state.speedTest.binaryReady -> "已就绪（arm64）"
                        else -> "未安装 / 需 fetch-cfst"
                    },
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
                        onClick = onRefreshCfstStatus,
                        enabled = !state.speedTest.isRunning,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("检查 CFST 组件")
                    }
                    Text(
                        text =
                            "mihomo / CFST 由 assets 安装到 filesDir；" +
                                "更新：scripts/fetch-mihomo.mjs、scripts/fetch-cfst.mjs（仅 arm64）。" +
                                "生产级 tun2socks / 完整 UDP·IPv6 转发仍在路线图中。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            SurfaceCard {
                CardHeader(title = "数据", icon = Icons.Outlined.DeleteForever, tone = AppTone.Warning)
                HorizontalDivider(color = colors.surfaceBorder)
                Column(modifier = Modifier.padding(VisualStyle.spacing16)) {
                    Text(
                        "清除本机会话偏好（配置 YAML、节点候选、出口检测设置）。" +
                            "不会卸载 mihomo 二进制或撤销 VPN 权限。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(
                        onClick = onClearSessionData,
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
                CompactInfoRow("版本", "0.1.0")
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
