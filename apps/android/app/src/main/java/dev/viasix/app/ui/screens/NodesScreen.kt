package dev.viasix.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.ui.AppSection
import dev.viasix.app.ui.theme.AppPageHeader
import dev.viasix.app.ui.theme.AppTone
import dev.viasix.app.ui.theme.CardHeader
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.StatusBadge
import dev.viasix.app.ui.theme.SurfaceCard
import dev.viasix.app.ui.theme.VisualStyle

@Composable
fun NodesScreen(
    state: SessionUiState,
    onSelectedAddressChange: (String) -> Unit,
) {
    val colors = LocalViaSixColors.current
    val looksValid = state.selectedAddress.contains(':')

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.NODES.title,
            subtitle = AppSection.NODES.subtitle,
        ) {
            StatusBadge(
                title = if (looksValid) "已选择" else "未选择",
                tone = if (looksValid) AppTone.Accent else AppTone.Warning,
            )
        }

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
                    title = "当前 IPv6 节点",
                    icon = Icons.Outlined.Hub,
                    tone = if (looksValid) AppTone.Accent else AppTone.Warning,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    OutlinedTextField(
                        value = state.selectedAddress,
                        onValueChange = onSelectedAddressChange,
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("选中 IPv6") },
                        singleLine = true,
                        textStyle =
                            MaterialTheme.typography.bodyLarge.copy(
                                fontFamily = FontFamily.Monospace,
                            ),
                        supportingText = {
                            Text("写入运行配置的 primary-server / selected-ip")
                        },
                    )
                }
            }

            SurfaceCard {
                CardHeader(
                    title = "说明",
                    icon = Icons.Outlined.Info,
                    tone = AppTone.Neutral,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                ) {
                    Text(
                        text =
                            "macOS 端提供 CloudflareSpeedTest 测速与结果表；" +
                                "Android 当前为手动指定 IPv6。测速与排序将在后续版本对齐。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text =
                            "直连模式下不需要 IPv6 节点；规则 / 全局模式要求地址为合法 IPv6，" +
                                "否则投影会返回 selectedNodeMustBeIPv6。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}
