package dev.viasix.app.ui.screens

import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.automirrored.outlined.PlaylistAddCheck
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
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
import dev.viasix.core.net.Ipv6Address
import dev.viasix.core.speedtest.Ipv6IpPresets
import dev.viasix.core.speedtest.NodeSortKey
import dev.viasix.core.speedtest.SpeedTestResult

@Composable
fun NodesScreen(
    state: SessionUiState,
    onSelectedAddressChange: (String) -> Unit,
    onApplyNode: (address: String, reconnect: Boolean) -> Unit,
    onRemoveCandidate: (String) -> Unit,
    onCopy: (label: String, value: String) -> Unit,
    onSpeedIpRangeChange: (String) -> Unit = {},
    onSpeedUseBundledChange: (Boolean) -> Unit = {},
    onSpeedDisableDownloadChange: (Boolean) -> Unit = {},
    onStartSpeedTest: () -> Unit = {},
    onStopSpeedTest: () -> Unit = {},
    onStartCurrentNodeTest: () -> Unit = {},
    onSpeedSortChange: (NodeSortKey) -> Unit = {},
) {
    val colors = LocalViaSixColors.current
    val looksValid = Ipv6Address.isValid(state.selectedAddress)
    val speed = state.speedTest

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.NODES.title,
            subtitle = AppSection.NODES.subtitle,
        ) {
            StatusBadge(
                title =
                    when {
                        speed.isRunning -> "测速中"
                        looksValid -> "已选择"
                        else -> "未选择"
                    },
                tone =
                    when {
                        speed.isRunning -> AppTone.Warning
                        looksValid -> AppTone.Accent
                        else -> AppTone.Warning
                    },
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
                    title = "CloudflareSpeedTest",
                    icon = Icons.Outlined.Speed,
                    tone = if (speed.isRunning) AppTone.Warning else AppTone.Accent,
                ) {
                    StatusBadge(
                        if (speed.binaryReady) "CFST 就绪" else "需拉取二进制",
                        tone = if (speed.binaryReady) AppTone.Accent else AppTone.Neutral,
                    )
                }
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    Text(
                        speed.message,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            "使用内置 IPv6 列表",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                        Switch(
                            checked = speed.useBundledList,
                            onCheckedChange = onSpeedUseBundledChange,
                            enabled = !speed.isRunning,
                        )
                    }

                    if (!speed.useBundledList) {
                        Row(
                            modifier =
                                Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                        ) {
                            Ipv6IpPresets.all.forEach { preset ->
                                FilterChip(
                                    selected = speed.ipRange == preset.ipRange,
                                    onClick = { onSpeedIpRangeChange(preset.ipRange) },
                                    enabled = !speed.isRunning,
                                    label = { Text(preset.title) },
                                )
                            }
                        }
                        OutlinedTextField(
                            value = speed.ipRange,
                            onValueChange = onSpeedIpRangeChange,
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("IP / CIDR（逗号分隔）") },
                            enabled = !speed.isRunning,
                            textStyle =
                                MaterialTheme.typography.bodyMedium.copy(
                                    fontFamily = FontFamily.Monospace,
                                ),
                            supportingText = {
                                Text("对应 CFST -ip；与 macOS / Windows 测速源一致")
                            },
                        )
                    } else {
                        Text(
                            "使用 assets 内置 ipv6.txt（CFST -f），与 macOS 默认列表核心段对齐。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }

                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            "跳过下载测速（仅延迟）",
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                        Switch(
                            checked = speed.disableDownload,
                            onCheckedChange = onSpeedDisableDownloadChange,
                            enabled = !speed.isRunning,
                        )
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                    ) {
                        Button(
                            onClick = onStartSpeedTest,
                            enabled = !speed.isRunning,
                            modifier = Modifier.weight(1f),
                        ) {
                            Text(
                                when {
                                    speed.isRunning && !speed.isNodeTest -> "测速中…"
                                    else -> "开始测速"
                                },
                            )
                        }
                        OutlinedButton(
                            onClick = onStopSpeedTest,
                            enabled = speed.isRunning,
                            modifier = Modifier.weight(1f),
                        ) {
                            Text("停止")
                        }
                    }
                    OutlinedButton(
                        onClick = onStartCurrentNodeTest,
                        enabled = !speed.isRunning && looksValid,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            if (speed.isRunning && speed.isNodeTest) {
                                "当前节点测速中…"
                            } else {
                                "当前节点测速"
                            },
                        )
                    }
                    Text(
                        "「当前节点测速」仅对选中 IPv6 运行 CFST（对齐 macOS 配置测速），结果可应用 / 重连。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (speed.results.isNotEmpty()) {
                SurfaceCard {
                    CardHeader(
                        title = "测速结果",
                        icon = Icons.Outlined.Speed,
                        tone = AppTone.Accent,
                    ) {
                        StatusBadge("${speed.results.size}", tone = AppTone.Neutral)
                    }
                    HorizontalDivider(color = colors.surfaceBorder)
                    Column(
                        modifier = Modifier.padding(top = VisualStyle.spacing8),
                        verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                    ) {
                        Text(
                            "排序（再点同一列切换升/降序；缺失值始终靠后）",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = VisualStyle.spacing16),
                        )
                        Row(
                            modifier =
                                Modifier
                                    .fillMaxWidth()
                                    .horizontalScroll(rememberScrollState())
                                    .padding(horizontal = VisualStyle.spacing12),
                            horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                        ) {
                            SortChip(
                                label = "延迟",
                                key = NodeSortKey.LATENCY,
                                current = speed.sortKey,
                                ascending = speed.sortAscending,
                                onClick = onSpeedSortChange,
                            )
                            SortChip(
                                label = "丢包",
                                key = NodeSortKey.LOSS,
                                current = speed.sortKey,
                                ascending = speed.sortAscending,
                                onClick = onSpeedSortChange,
                            )
                            SortChip(
                                label = "速度",
                                key = NodeSortKey.SPEED,
                                current = speed.sortKey,
                                ascending = speed.sortAscending,
                                onClick = onSpeedSortChange,
                            )
                            SortChip(
                                label = "地区",
                                key = NodeSortKey.REGION,
                                current = speed.sortKey,
                                ascending = speed.sortAscending,
                                onClick = onSpeedSortChange,
                            )
                            SortChip(
                                label = "IP",
                                key = NodeSortKey.IP,
                                current = speed.sortKey,
                                ascending = speed.sortAscending,
                                onClick = onSpeedSortChange,
                            )
                        }
                        HorizontalDivider(color = colors.surfaceBorder)
                        val sorted = speed.sortedResults
                        sorted.forEachIndexed { index, row ->
                            SpeedResultRow(
                                result = row,
                                vpnRunning = state.runtime.running,
                                onApply = { onApplyNode(row.ip, false) },
                                onApplyReconnect = { onApplyNode(row.ip, true) },
                                onCopy = { onCopy("IPv6", row.ip) },
                            )
                            if (index != sorted.lastIndex) {
                                HorizontalDivider(
                                    color = colors.surfaceBorder,
                                    modifier = Modifier.padding(start = 16.dp),
                                )
                            }
                        }
                    }
                }
            }

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
                            Text(
                                if (looksValid) {
                                    "合法 IPv6 · 将作为 primary-server 注入运行配置"
                                } else {
                                    "需要合法 IPv6（支持 [brackets] 与 zone id 规范化）"
                                },
                            )
                        },
                        isError = state.selectedAddress.isNotBlank() && !looksValid,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                    ) {
                        Button(
                            onClick = { onApplyNode(state.selectedAddress, false) },
                            enabled = looksValid,
                            modifier = Modifier.weight(1f),
                        ) {
                            Text("应用节点")
                        }
                        FilledTonalButton(
                            onClick = { onApplyNode(state.selectedAddress, true) },
                            enabled = looksValid && state.runtime.running,
                            modifier = Modifier.weight(1f),
                        ) {
                            Text("应用并重连")
                        }
                    }
                    if (state.runtime.running) {
                        Text(
                            "「应用并重连」会短暂中断本地代理，并以所选节点重新建立 VpnService 会话。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            SurfaceCard {
                CardHeader(
                    title = "候选节点",
                    icon = Icons.AutoMirrored.Outlined.PlaylistAddCheck,
                    tone = AppTone.Accent,
                ) {
                    StatusBadge(
                        "${state.candidateAddresses.size}",
                        tone = AppTone.Neutral,
                    )
                }
                HorizontalDivider(color = colors.surfaceBorder)
                if (state.candidateAddresses.isEmpty()) {
                    Text(
                        "应用合法 IPv6 或测速结果后会出现在候选列表，便于快速切换。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(VisualStyle.spacing16),
                    )
                } else {
                    Column {
                        state.candidateAddresses.forEachIndexed { index, address ->
                            val selected = address == Ipv6Address.normalize(state.selectedAddress)
                            Row(
                                modifier =
                                    Modifier
                                        .fillMaxWidth()
                                        .padding(
                                            horizontal = VisualStyle.spacing12,
                                            vertical = VisualStyle.spacing8,
                                        ),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        address,
                                        style =
                                            MaterialTheme.typography.bodyMedium.copy(
                                                fontFamily = FontFamily.Monospace,
                                            ),
                                        maxLines = 2,
                                    )
                                    if (selected) {
                                        Text(
                                            "当前使用",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = colors.accent,
                                        )
                                    }
                                }
                                IconButton(onClick = { onCopy("IPv6", address) }) {
                                    Icon(Icons.Outlined.ContentCopy, contentDescription = "复制")
                                }
                                OutlinedButton(
                                    onClick = { onApplyNode(address, false) },
                                    modifier = Modifier.height(34.dp),
                                ) { Text("选用") }
                                if (state.runtime.running) {
                                    FilledTonalButton(
                                        onClick = { onApplyNode(address, true) },
                                        modifier = Modifier.height(34.dp),
                                    ) { Text("重连") }
                                }
                                IconButton(onClick = { onRemoveCandidate(address) }) {
                                    Icon(Icons.Outlined.Delete, contentDescription = "移除")
                                }
                            }
                            if (index != state.candidateAddresses.lastIndex) {
                                HorizontalDivider(
                                    color = colors.surfaceBorder,
                                    modifier = Modifier.padding(start = 16.dp),
                                )
                            }
                        }
                    }
                }
            }

            SurfaceCard {
                CardHeader(title = "说明", icon = Icons.Outlined.Info, tone = AppTone.Neutral)
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                ) {
                    Text(
                        "测速使用 CloudflareSpeedTest（CFST）v2.3.5 与 macOS / Windows 对齐：" +
                            "结果写入候选列表，选用或「应用并重连」走同一 projection / VpnService 路径。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "当前仅打包 arm64（linux_arm64）二进制；其他 ABI 需自行提供或等待后续扩展。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        "直连模式下不需要 IPv6 节点；规则 / 全局模式投影要求 selectedNodeMustBeIPv6。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun SortChip(
    label: String,
    key: NodeSortKey,
    current: NodeSortKey,
    ascending: Boolean,
    onClick: (NodeSortKey) -> Unit,
) {
    val selected = current == key
    val arrow =
        when {
            !selected -> ""
            ascending -> " ↑"
            else -> " ↓"
        }
    FilterChip(
        selected = selected,
        onClick = { onClick(key) },
        label = { Text("$label$arrow") },
    )
}

@Composable
private fun SpeedResultRow(
    result: SpeedTestResult,
    vpnRunning: Boolean,
    onApply: () -> Unit,
    onApplyReconnect: () -> Unit,
    onCopy: () -> Unit,
) {
    val valid = Ipv6Address.isValid(result.ip)
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = VisualStyle.spacing12,
                    vertical = VisualStyle.spacing8,
                ),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            result.ip,
            style =
                MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace,
                ),
            maxLines = 2,
        )
        Text(
            buildString {
                append("延迟 ${result.latency.ifBlank { "—" }}")
                append(" · 丢包 ${result.loss.ifBlank { "—" }}")
                append(" · 速度 ${result.speed.ifBlank { "—" }}")
                if (result.region.isNotBlank()) append(" · ${result.region}")
            },
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onCopy) {
                Icon(Icons.Outlined.ContentCopy, contentDescription = "复制")
            }
            OutlinedButton(
                onClick = onApply,
                enabled = valid,
                modifier = Modifier.height(34.dp),
            ) { Text("应用") }
            if (vpnRunning) {
                FilledTonalButton(
                    onClick = onApplyReconnect,
                    enabled = valid,
                    modifier = Modifier.height(34.dp),
                ) { Text("应用并重连") }
            }
        }
    }
}
