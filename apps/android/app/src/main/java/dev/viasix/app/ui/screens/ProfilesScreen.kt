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
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Science
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
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
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.StatusBadge
import dev.viasix.app.ui.theme.SurfaceCard
import dev.viasix.app.ui.theme.VisualStyle

@Composable
fun ProfilesScreen(
    state: SessionUiState,
    onProfileChange: (String) -> Unit,
    onProjectPreview: () -> Unit,
) {
    val colors = LocalViaSixColors.current
    val hasProfile = state.profileYaml.isNotBlank()

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.PROFILES.title,
            subtitle = AppSection.PROFILES.subtitle,
        ) {
            StatusBadge(
                title = if (hasProfile) "已配置" else "空",
                tone = if (hasProfile) AppTone.Accent else AppTone.Warning,
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
                    title = "当前代理入口",
                    icon = Icons.Outlined.Inventory2,
                    tone = if (hasProfile) AppTone.Accent else AppTone.Warning,
                )
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    Text(
                        text =
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
                        Button(onClick = onProjectPreview) {
                            Text("生成运行配置预览")
                        }
                    }
                }
            }

            if (state.configPreview.isNotBlank()) {
                SurfaceCard {
                    CardHeader(
                        title = "运行配置预览",
                        icon = Icons.Outlined.Science,
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
        }
    }
}
