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
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.ui.AppSection
import dev.viasix.app.ui.theme.AppPageHeader
import dev.viasix.app.ui.theme.AppTone
import dev.viasix.app.ui.theme.CardHeader
import dev.viasix.app.ui.theme.CompactInfoRow
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.StatusBadge
import dev.viasix.app.ui.theme.SurfaceCard
import dev.viasix.app.ui.theme.VisualStyle

@Composable
fun ProfilesScreen(
    state: SessionUiState,
    onProfileChange: (String) -> Unit,
    onProjectPreview: () -> Unit,
    onImportProfile: () -> Unit,
    onImportClipboard: () -> Unit = {},
) {
    val colors = LocalViaSixColors.current
    val summary = state.profileSummary
    val tone =
        when {
            summary.isManaged -> AppTone.Accent
            summary.primary != null -> AppTone.Warning
            else -> AppTone.Negative
        }

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.PROFILES.title,
            subtitle = AppSection.PROFILES.subtitle,
        ) {
            StatusBadge(summary.statusLabel, tone = tone)
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
                    title = "当前代理入口",
                    icon = Icons.Outlined.Inventory2,
                    tone = tone,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("名称", summary.primary?.name ?: "—")
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("类型", summary.primary?.type ?: "—")
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "服务端",
                    summary.primary?.let { primary ->
                        primary.server?.let { s ->
                            primary.port?.let { "$s:$it" } ?: s
                        } ?: "—"
                    } ?: "—",
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("proxies", "${summary.proxyCount}")
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "x-viasix",
                    if (summary.hasXViasix) {
                        summary.primaryServerMarker ?: "已声明"
                    } else {
                        "缺失"
                    },
                )
                if (summary.warnings.isNotEmpty()) {
                    Column(
                        modifier = Modifier.padding(VisualStyle.spacing16),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        summary.warnings.forEach { warning ->
                            Text(
                                "• $warning",
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.warning,
                            )
                        }
                    }
                } else {
                    androidx.compose.foundation.layout.Spacer(
                        Modifier.height(VisualStyle.spacing12),
                    )
                }
            }

            SurfaceCard {
                CardHeader(
                    title = "编辑 YAML",
                    icon = Icons.Outlined.Science,
                    tone = AppTone.Accent,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    Text(
                        "粘贴或编辑 mihomo 兼容 YAML。须包含 x-viasix 管理段，" +
                            "与 contracts 及 macOS / Windows 投影语义一致。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedTextField(
                        value = state.profileYaml,
                        onValueChange = onProfileChange,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .height(280.dp),
                        label = { Text("Profile YAML") },
                        textStyle =
                            MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                            ),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                    ) {
                        OutlinedButton(onClick = onImportProfile) {
                            Text("导入文件")
                        }
                        OutlinedButton(onClick = onImportClipboard) {
                            Text("粘贴剪贴板")
                        }
                    }
                    Button(
                        onClick = onProjectPreview,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("生成运行配置预览")
                    }
                }
            }

            if (state.configPreview.isNotBlank()) {
                SurfaceCard {
                    CardHeader(
                        title = "运行配置预览",
                        icon = Icons.Outlined.FileOpen,
                        tone = AppTone.Accent,
                    )
                    HorizontalDivider(color = colors.surfaceBorder)
                    Text(
                        text = state.configPreview,
                        style =
                            MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                            ),
                        modifier = Modifier.padding(VisualStyle.spacing16),
                    )
                }
            }

            SurfaceCard {
                CardHeader(
                    title = "安全提示",
                    icon = Icons.Outlined.Shield,
                    tone = AppTone.Warning,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                Text(
                    text =
                        "配置仅保存在本机 SharedPreferences，不会上传。" +
                            "请勿分享含有 uuid / 密钥的完整 YAML。" +
                            "投影前请确认 x-viasix.version 与 contracts 一致。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(VisualStyle.spacing16),
                )
            }

            if (!summary.isManaged) {
                SurfaceCard {
                    CardHeader(
                        title = "配置不完整",
                        icon = Icons.Outlined.WarningAmber,
                        tone = AppTone.Warning,
                    )
                    HorizontalDivider(color = colors.surfaceBorder)
                    Text(
                        "规则/全局模式需要带 x-viasix 的托管入口，否则启动时投影会失败。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(VisualStyle.spacing16),
                    )
                }
            }
        }
    }
}
