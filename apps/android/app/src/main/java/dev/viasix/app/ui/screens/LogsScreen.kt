package dev.viasix.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.viasix.app.state.LogLevel
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
fun LogsScreen(
    state: SessionUiState,
    onClear: () -> Unit,
) {
    val colors = LocalViaSixColors.current

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.LOGS.title,
            subtitle = AppSection.LOGS.subtitle,
        ) {
            StatusBadge(
                title = "${state.logs.size} 条",
                tone = AppTone.Neutral,
            )
            IconButton(onClick = onClear) {
                Icon(
                    imageVector = Icons.Outlined.DeleteSweep,
                    contentDescription = "清空日志",
                )
            }
        }

        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(
                        horizontal = VisualStyle.pageHorizontalPadding,
                        vertical = VisualStyle.pageVerticalPadding,
                    ),
            verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
        ) {
            SurfaceCard(modifier = Modifier.fillMaxSize()) {
                CardHeader(
                    title = "会话活动",
                    icon = Icons.AutoMirrored.Outlined.Article,
                    tone = AppTone.Neutral,
                )
                HorizontalDivider(color = colors.surfaceBorder)

                if (state.logs.isEmpty()) {
                    Text(
                        text = "连接、停止、投影与运行时状态会显示在这里。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(VisualStyle.spacing16),
                    )
                } else {
                    LazyColumn(modifier = Modifier.fillMaxSize()) {
                        items(state.logs, key = { it.id }) { entry ->
                            Row(
                                modifier =
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(
                                            horizontal = VisualStyle.spacing16,
                                            vertical = VisualStyle.spacing8,
                                        ),
                                verticalAlignment = Alignment.Top,
                                horizontalArrangement =
                                    Arrangement.spacedBy(VisualStyle.spacing12),
                            ) {
                                Text(
                                    text = entry.timestamp,
                                    style =
                                        MaterialTheme.typography.labelMedium.copy(
                                            fontFamily = FontFamily.Monospace,
                                            fontWeight = FontWeight.Medium,
                                        ),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(
                                    text = entry.message,
                                    style = MaterialTheme.typography.bodySmall,
                                    color =
                                        when (entry.level) {
                                            LogLevel.Error -> colors.negative
                                            LogLevel.Success -> colors.positive
                                            LogLevel.Info ->
                                                MaterialTheme.colorScheme.onSurface
                                        },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                            HorizontalDivider(
                                color = colors.surfaceBorder.copy(alpha = 0.5f),
                                modifier = Modifier.padding(start = 72.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}
