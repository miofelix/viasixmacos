package dev.viasix.app.ui.screens

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.SwapVert
import androidx.compose.material.icons.outlined.VerticalAlignBottom
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.viasix.app.state.LogLevel
import dev.viasix.app.state.LogFollowState
import dev.viasix.app.state.LogOrder
import dev.viasix.app.state.LogSource
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.ui.AppSection
import dev.viasix.app.ui.theme.AppPageHeader
import dev.viasix.app.ui.theme.AppTone
import dev.viasix.app.ui.theme.CardHeader
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.StatusBadge
import dev.viasix.app.ui.theme.SurfaceCard
import dev.viasix.app.ui.theme.VisualStyle

private enum class LevelFilter(val label: String) {
    All("全部级别"),
    Info("信息"),
    Success("成功"),
    Warning("警告"),
    Error("错误"),
}

private enum class SourceFilter(val label: String, val source: LogSource?) {
    All("全部来源", null),
    Session("会话", LogSource.Session),
    Proxy("代理", LogSource.Proxy),
    Node("节点", LogSource.Node),
    Network("网络", LogSource.Network),
    System("系统", LogSource.System),
}

@Composable
fun LogsScreen(
    state: SessionUiState,
    onClear: () -> Unit,
) {
    val colors = LocalViaSixColors.current
    var search by remember { mutableStateOf("") }
    var levelFilter by remember { mutableStateOf(LevelFilter.All) }
    var sourceFilter by remember { mutableStateOf(SourceFilter.All) }
    var followState by remember { mutableStateOf(LogFollowState()) }
    var showsClearConfirmation by remember { mutableStateOf(false) }
    val newestFirst = followState.order == LogOrder.NEWEST_FIRST
    val listState = rememberLazyListState()

    val filtered =
        remember(state.logs, search, levelFilter, sourceFilter, newestFirst) {
            var list = state.logs.asSequence()
            if (search.isNotBlank()) {
                val q = search.trim()
                list = list.filter { it.message.contains(q, ignoreCase = true) }
            }
            list =
                when (levelFilter) {
                    LevelFilter.All -> list
                    LevelFilter.Info -> list.filter { it.level == LogLevel.Info }
                    LevelFilter.Success -> list.filter { it.level == LogLevel.Success }
                    LevelFilter.Warning -> list.filter { it.level == LogLevel.Warning }
                    LevelFilter.Error -> list.filter { it.level == LogLevel.Error }
                }
            val source = sourceFilter.source
            if (source != null) {
                list = list.filter { it.source == source }
            }
            val result = list.toList()
            // logs stored newest-first; reverse when newestFirst is false
            if (newestFirst) result else result.asReversed()
        }

    val latestVisibleId =
        if (followState.canFollowLatest) {
            filtered.lastOrNull()?.id
        } else {
            null
        }
    LaunchedEffect(
        latestVisibleId,
        filtered.size,
        followState.order,
        followState.followsLatest,
    ) {
        if (followState.canFollowLatest && followState.followsLatest && filtered.isNotEmpty()) {
            listState.scrollToItem(filtered.lastIndex)
        }
    }

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.LOGS.title,
            subtitle = AppSection.LOGS.subtitle,
        ) {
            StatusBadge(
                title = "${filtered.size}/${state.logs.size}",
                tone = AppTone.Neutral,
            )
            IconButton(
                onClick = { followState = followState.toggleOrder() },
                enabled = state.logs.isNotEmpty(),
            ) {
                Icon(
                    imageVector = Icons.Outlined.SwapVert,
                    contentDescription = if (newestFirst) "切换为最旧在上" else "切换为最新在上",
                )
            }
            IconButton(
                onClick = { followState = followState.toggleFollowing() },
                enabled = state.logs.isNotEmpty() && followState.canFollowLatest,
            ) {
                Icon(
                    imageVector =
                        if (followState.followsLatest) {
                            Icons.Outlined.Pause
                        } else {
                            Icons.Outlined.VerticalAlignBottom
                        },
                    contentDescription =
                        if (followState.followsLatest) "暂停跟随最新日志" else "恢复跟随最新日志",
                )
            }
            IconButton(
                onClick = { showsClearConfirmation = true },
                enabled = state.logs.isNotEmpty(),
            ) {
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
            SurfaceCard {
                Column(modifier = Modifier.padding(VisualStyle.spacing12)) {
                    OutlinedTextField(
                        value = search,
                        onValueChange = { search = it },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text("搜索") },
                        placeholder = { Text("过滤消息内容") },
                    )
                    Row(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                                .padding(top = VisualStyle.spacing8),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        LevelFilter.entries.forEach { filter ->
                            FilterChip(
                                selected = levelFilter == filter,
                                onClick = { levelFilter = filter },
                                label = { Text(filter.label) },
                            )
                        }
                    }
                    Row(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .horizontalScroll(rememberScrollState())
                                .padding(top = VisualStyle.spacing4),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        SourceFilter.entries.forEach { filter ->
                            FilterChip(
                                selected = sourceFilter == filter,
                                onClick = { sourceFilter = filter },
                                label = { Text(filter.label) },
                            )
                        }
                    }
                }
            }

            SurfaceCard(modifier = Modifier.fillMaxSize()) {
                CardHeader(
                    title = "会话活动",
                    icon = Icons.AutoMirrored.Outlined.Article,
                    tone = AppTone.Neutral,
                )
                HorizontalDivider(color = colors.surfaceBorder)

                if (filtered.isEmpty()) {
                    Text(
                        text =
                            if (state.logs.isEmpty()) {
                                "连接、停止、投影、出口检测与 VPN 事件会显示在这里。"
                            } else {
                                "没有符合当前过滤条件的记录。"
                            },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(VisualStyle.spacing16),
                    )
                } else {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(filtered, key = { it.id }) { entry ->
                            Row(
                                modifier =
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(
                                            horizontal = VisualStyle.spacing16,
                                            vertical = VisualStyle.spacing8,
                                        ),
                                verticalAlignment = Alignment.Top,
                                horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
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
                                    text = entry.source.label,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = colors.accent,
                                    modifier = Modifier.padding(top = 2.dp),
                                )
                                Text(
                                    text = entry.message,
                                    style = MaterialTheme.typography.bodySmall,
                                    color =
                                        when (entry.level) {
                                            LogLevel.Error -> colors.negative
                                            LogLevel.Success -> colors.positive
                                            LogLevel.Warning -> colors.warning
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

    if (showsClearConfirmation) {
        AlertDialog(
            onDismissRequest = { showsClearConfirmation = false },
            title = { Text("清空日志？") },
            text = { Text("这会移除全部会话记录，且无法撤销。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showsClearConfirmation = false
                        followState = followState.resetAfterClear()
                        onClear()
                    },
                ) {
                    Text("清空")
                }
            },
            dismissButton = {
                TextButton(onClick = { showsClearConfirmation = false }) {
                    Text("取消")
                }
            },
        )
    }
}
