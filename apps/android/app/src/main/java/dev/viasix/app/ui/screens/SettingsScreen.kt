package dev.viasix.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
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
import androidx.compose.material3.TextButton

@Composable
fun SettingsScreen(
    state: SessionUiState,
    onFullTunnelChange: (Boolean) -> Unit,
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
                CardHeader(
                    title = "网络接入",
                    icon = Icons.Outlined.VpnKey,
                    tone = AppTone.Accent,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                SettingRow(
                    title = "全量隧道",
                    detail = "默认路由 + 用户态 IPv4 TCP→SOCKS 与 DNS protect",
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
                            "依赖应用自身代理感知。Android 无系统级 HTTP/SOCKS 代理开关。",
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
                CardHeader(
                    title = "运行组件",
                    icon = Icons.Outlined.Settings,
                    tone = AppTone.Neutral,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("内核", "mihomo（assets → filesDir）")
                HorizontalDivider(
                    color = colors.surfaceBorder,
                    modifier = Modifier.padding(start = 40.dp),
                )
                CompactInfoRow("混合端口", "127.0.0.1:${state.runtime.mixedPort}")
                HorizontalDivider(
                    color = colors.surfaceBorder,
                    modifier = Modifier.padding(start = 40.dp),
                )
                CompactInfoRow("控制器", "127.0.0.1:${state.runtime.controllerPort}")
                HorizontalDivider(
                    color = colors.surfaceBorder,
                    modifier = Modifier.padding(start = 40.dp),
                )
                CompactInfoRow("路由模式", state.routingMode.displayName())
                HorizontalDivider(
                    color = colors.surfaceBorder,
                    modifier = Modifier.padding(start = 40.dp),
                )
                CompactInfoRow(
                    "健康",
                    state.runtime.health.ifBlank { "—" },
                )
                Text(
                    text =
                        "mihomo 由应用内预编译二进制启动；更新可用 scripts/fetch-mihomo.mjs。" +
                            "生产级 tun2socks / 完整 UDP·IPv6 转发仍在路线图中。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier =
                        Modifier.padding(
                            start = VisualStyle.spacing16,
                            end = VisualStyle.spacing16,
                            bottom = VisualStyle.spacing12,
                            top = VisualStyle.spacing8,
                        ),
                )
            }

            SurfaceCard {
                CardHeader(
                    title = "关于 ViaSix",
                    icon = Icons.Outlined.Info,
                    tone = AppTone.Neutral,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("版本", "0.1.0")
                HorizontalDivider(
                    color = colors.surfaceBorder,
                    modifier = Modifier.padding(start = 40.dp),
                )
                CompactInfoRow("平台", "Android · VpnService")
                HorizontalDivider(
                    color = colors.surfaceBorder,
                    modifier = Modifier.padding(start = 40.dp),
                )
                CompactInfoRow("契约", "contracts/fixtures · 与桌面端对齐")
                TextButton(
                    onClick = {
                        uriHandler.openUri("https://github.com/miofelix/ViaSix")
                    },
                    modifier = Modifier.padding(horizontal = VisualStyle.spacing8),
                ) {
                    Text("打开 GitHub 仓库")
                }
            }
        }
    }
}
