package dev.viasix.app.ui.screens

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Route
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.viasix.app.BuildConfig
import dev.viasix.app.net.ExitIPDetectionMode
import dev.viasix.app.session.AppRoutingMode
import dev.viasix.app.session.ConnectionPhase
import dev.viasix.app.state.LogLevel
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.ui.AppSection
import dev.viasix.app.ui.description
import dev.viasix.app.ui.displayName
import dev.viasix.app.ui.theme.AppPageHeader
import dev.viasix.app.ui.theme.AppTone
import dev.viasix.app.ui.theme.CardHeader
import dev.viasix.app.ui.theme.CompactInfoRow
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.MetricTile
import dev.viasix.app.ui.theme.SettingRow
import dev.viasix.app.ui.theme.StatusBadge
import dev.viasix.app.ui.theme.SurfaceCard
import dev.viasix.app.ui.theme.VisualStyle
import dev.viasix.core.formatting.ByteRateFormatter
import dev.viasix.core.projection.RoutingMode

@Composable
fun OverviewScreen(
    state: SessionUiState,
    onRoutingModeChange: (RoutingMode) -> Unit,
    onFullTunnelChange: (Boolean) -> Unit,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onNavigate: (AppSection) -> Unit,
    onDetectExitIp: () -> Unit,
    onExitIpModeChange: (ExitIPDetectionMode) -> Unit,
    onDelayTest: () -> Unit,
    onCopy: (label: String, value: String) -> Unit,
    onStartCurrentNodeTest: () -> Unit = {},
    onStopSpeedTest: () -> Unit = {},
) {
    val colors = LocalViaSixColors.current
    val phase = state.connectionPhase
    val running = phase == ConnectionPhase.RUNNING || state.runtime.running
    val selectedIsIpv6 = state.selectedIsIpv6
    val profileReady = state.configurationReady
    val headerTone =
        when {
            phase == ConnectionPhase.RUNNING || running -> AppTone.Positive
            phase == ConnectionPhase.STARTING || phase == ConnectionPhase.STOPPING -> AppTone.Warning
            state.statusLevel == LogLevel.Error -> AppTone.Negative
            else -> AppTone.Neutral
        }
    val headerStatus =
        when {
            state.statusLevel == LogLevel.Error && phase == ConnectionPhase.STOPPED -> "异常"
            else -> phase.statusLabel()
        }

    Column(Modifier.fillMaxSize()) {
        AppPageHeader(
            title = AppSection.OVERVIEW.title,
            subtitle = AppSection.OVERVIEW.subtitle,
        ) {
            StatusBadge(headerStatus, tone = headerTone)
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
            // Clash Meta / NekoBox-style primary power control on home.
            SurfaceCard {
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = phase.statusLabel(),
                                style =
                                    MaterialTheme.typography.headlineSmall.copy(
                                        fontWeight = FontWeight.SemiBold,
                                    ),
                                color =
                                    when (phase) {
                                        ConnectionPhase.RUNNING -> colors.positive
                                        ConnectionPhase.STARTING,
                                        ConnectionPhase.STOPPING,
                                        -> colors.warning
                                        ConnectionPhase.STOPPED -> MaterialTheme.colorScheme.onSurface
                                    },
                            )
                            Text(
                                text =
                                    when {
                                        phase == ConnectionPhase.STARTING ->
                                            "正在建立 VPN 与 mihomo…"
                                        phase == ConnectionPhase.STOPPING ->
                                            "正在停止会话…"
                                        running && state.runtime.traffic.live ->
                                            state.runtime.traffic.message
                                        running -> state.runtime.health
                                        else ->
                                            if (state.fullTunnel) {
                                                "点按连接 · 全量隧道"
                                            } else {
                                                "点按连接 · HTTP 代理 VPN"
                                            }
                                    },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        when (phase) {
                            ConnectionPhase.RUNNING,
                            ConnectionPhase.STARTING,
                            -> {
                                // STARTING: allow cancel (stop), like macOS.
                                OutlinedButton(
                                    onClick = onStop,
                                    enabled = phase != ConnectionPhase.STOPPING,
                                    modifier =
                                        Modifier
                                            .height(52.dp)
                                            .padding(start = VisualStyle.spacing4),
                                ) {
                                    Text(
                                        if (phase == ConnectionPhase.STARTING) "取消" else "断开",
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            }
                            ConnectionPhase.STOPPING -> {
                                OutlinedButton(
                                    onClick = {},
                                    enabled = false,
                                    modifier =
                                        Modifier
                                            .height(52.dp)
                                            .padding(start = VisualStyle.spacing4),
                                ) {
                                    Text("断开中…", fontWeight = FontWeight.SemiBold)
                                }
                            }
                            ConnectionPhase.STOPPED -> {
                                Button(
                                    onClick = onStart,
                                    enabled = profileReady || state.routingMode == RoutingMode.DIRECT,
                                    modifier =
                                        Modifier
                                            .height(52.dp)
                                            .padding(start = VisualStyle.spacing4),
                                ) {
                                    Text("连接", fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }
                    if (running && state.runtime.traffic.live) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                        ) {
                            MetricTile(
                                title = "上传",
                                value = ByteRateFormatter.formatRate(state.runtime.traffic.upBps),
                                tone = AppTone.Accent,
                                modifier = Modifier.weight(1f),
                            )
                            MetricTile(
                                title = "下载",
                                value = ByteRateFormatter.formatRate(state.runtime.traffic.downBps),
                                tone = AppTone.Positive,
                                modifier = Modifier.weight(1f),
                            )
                            MetricTile(
                                title = "连接",
                                value = state.runtime.traffic.connectionCount.toString(),
                                tone = AppTone.Neutral,
                                modifier = Modifier.weight(1f),
                            )
                        }
                    }
                }
            }

            SurfaceCard {
                CardHeader(
                    title = "IPv6 链路",
                    icon = Icons.Outlined.VpnKey,
                    tone = headerTone,
                ) {
                    StatusBadge(headerStatus, tone = headerTone)
                }
                HorizontalDivider(color = colors.surfaceBorder)
                LinkStep(
                    title = "网络接入",
                    detail =
                        if (state.fullTunnel) {
                            "VpnService 全量隧道（TCP/UDP IPv4/IPv6→SOCKS；DNS protect）"
                        } else {
                            "仅 HTTP 代理 VPN（无默认路由）"
                        },
                    ready = true,
                    active = running,
                    actionTitle = "设置",
                    onAction = { onNavigate(AppSection.SETTINGS) },
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 52.dp))
                LinkStep(
                    title = "IPv6 节点",
                    detail =
                        if (selectedIsIpv6) state.selectedAddress else "尚未选择有效 IPv6 地址",
                    ready = selectedIsIpv6 || state.routingMode == RoutingMode.DIRECT,
                    active = selectedIsIpv6 && running,
                    actionTitle = if (selectedIsIpv6) "更换" else "选择",
                    onAction = { onNavigate(AppSection.NODES) },
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 52.dp))
                LinkStep(
                    title = "连接配置",
                    detail =
                        when {
                            state.routingMode == RoutingMode.DIRECT -> "直连模式，无需入口配置"
                            state.profileSummary.isManaged ->
                                state.profileSummary.primary?.let {
                                    "${it.name} · ${it.type}"
                                } ?: "代理入口配置已就绪"
                            else -> state.profileSummary.statusLabel
                        },
                    ready = profileReady || state.routingMode == RoutingMode.DIRECT,
                    active = running && profileReady,
                    actionTitle = "管理",
                    onAction = { onNavigate(AppSection.PROFILES) },
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 52.dp))
                LinkStep(
                    title = "公网流量",
                    detail =
                        when {
                            running && state.runtime.traffic.live -> state.runtime.traffic.message
                            running -> state.runtime.health
                            else -> "启动连接后转发公网流量"
                        },
                    ready = profileReady || state.routingMode == RoutingMode.DIRECT,
                    active = running,
                )
                Spacer(Modifier.height(VisualStyle.spacing12))
            }

            // Routing mode
            SurfaceCard {
                CardHeader(title = "代理模式", icon = Icons.Outlined.Route, tone = AppTone.Accent)
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth().selectableGroup(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing8),
                    ) {
                        RoutingMode.entries.forEach { mode ->
                            val selected = state.routingMode == mode
                            val shape = RoundedCornerShape(8.dp)
                            Text(
                                text = mode.displayName(),
                                modifier =
                                    Modifier
                                        .weight(1f)
                                        .clip(shape)
                                        .background(if (selected) colors.accent else colors.elevatedSurface)
                                        .border(
                                            1.dp,
                                            if (selected) colors.accent else colors.surfaceBorder,
                                            shape,
                                        )
                                        .selectable(
                                            selected = selected,
                                            onClick = { onRoutingModeChange(mode) },
                                            role = Role.RadioButton,
                                        )
                                        .padding(vertical = 10.dp),
                                color = if (selected) Color.White else MaterialTheme.colorScheme.onSurface,
                                style =
                                    MaterialTheme.typography.labelLarge.copy(
                                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                                    ),
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                    Text(
                        text = state.routingMode.description(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(7.dp))
                                .background(colors.subtleFill)
                                .border(1.dp, colors.accent.copy(alpha = 0.38f), RoundedCornerShape(7.dp))
                                .padding(horizontal = 10.dp, vertical = 8.dp),
                    )
                    if (running) {
                        Text(
                            "连接中切换模式会尝试 PATCH /configs；失败则下次连接生效。",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            // Network
            SurfaceCard {
                CardHeader(title = "网络设置", icon = Icons.Outlined.Language, tone = AppTone.Accent)
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow(
                    "底层网络",
                    state.runtime.underlyingNetwork,
                    Icons.Outlined.Language,
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                SettingRow(
                    title = "全量隧道",
                    detail =
                        if (state.fullTunnel) {
                            "默认路由 + TCP/UDP IPv4/IPv6→SOCKS；" +
                                "DNS ${state.dnsSettings.mode.label} · MTU ${state.vpnMtu}" +
                                " · IPv6 ${state.ipv6RoutingMode.label}" +
                                if (
                                    state.bypassLocalNetwork &&
                                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                                ) {
                                    " · 绕过局域网"
                                } else {
                                    ""
                                }
                        } else {
                            "仅 setHttpProxy，无默认路由 · MTU ${state.vpnMtu}"
                        },
                    icon = Icons.Outlined.VpnKey,
                ) {
                    Switch(
                        checked = state.fullTunnel,
                        onCheckedChange = onFullTunnelChange,
                        enabled = !phase.isActiveOrTransitioning,
                    )
                }
                Text(
                    text =
                        "Android 使用 VpnService 作为虚拟网卡路径，无系统代理。" +
                            "全量隧道会排除本应用 UID 以防环路。" +
                            if (phase.isActiveOrTransitioning) {
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
            }

            // Traffic with sparkline
            SurfaceCard {
                CardHeader(
                    title = "流量统计",
                    icon = Icons.Outlined.Speed,
                    tone =
                        if (running && state.runtime.traffic.live) {
                            AppTone.Positive
                        } else {
                            AppTone.Neutral
                        },
                ) {
                    StatusBadge(
                        title =
                            when {
                                !running -> "未连接"
                                state.runtime.traffic.live -> "实时"
                                else -> "连接中"
                            },
                        tone =
                            when {
                                !running -> AppTone.Neutral
                                state.runtime.traffic.live -> AppTone.Positive
                                else -> AppTone.Warning
                            },
                    )
                }
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    TrafficSparkline(
                        points = state.runtime.traffic.history,
                        accent = colors.accent,
                        positive = colors.positive,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .height(96.dp)
                                .clip(RoundedCornerShape(VisualStyle.radiusMedium))
                                .background(colors.subtleFill)
                                .padding(8.dp),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                    ) {
                        MetricTile(
                            title = "上传",
                            value =
                                if (state.runtime.traffic.live) {
                                    ByteRateFormatter.formatRate(state.runtime.traffic.upBps)
                                } else {
                                    "—"
                                },
                            tone = AppTone.Accent,
                            modifier = Modifier.weight(1f),
                        )
                        MetricTile(
                            title = "下载",
                            value =
                                if (state.runtime.traffic.live) {
                                    ByteRateFormatter.formatRate(state.runtime.traffic.downBps)
                                } else {
                                    "—"
                                },
                            tone = AppTone.Positive,
                            modifier = Modifier.weight(1f),
                        )
                        MetricTile(
                            title = "内存",
                            value =
                                if (state.runtime.traffic.memoryInUse > 0) {
                                    ByteRateFormatter.formatBytes(state.runtime.traffic.memoryInUse)
                                } else {
                                    "—"
                                },
                            tone = AppTone.Warning,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                    ) {
                        MetricTile(
                            title = "总上传",
                            value =
                                if (state.runtime.traffic.live) {
                                    ByteRateFormatter.formatBytes(state.runtime.traffic.uploadTotal)
                                } else {
                                    "—"
                                },
                            tone = AppTone.Accent,
                            modifier = Modifier.weight(1f),
                        )
                        MetricTile(
                            title = "总下载",
                            value =
                                if (state.runtime.traffic.live) {
                                    ByteRateFormatter.formatBytes(state.runtime.traffic.downloadTotal)
                                } else {
                                    "—"
                                },
                            tone = AppTone.Positive,
                            modifier = Modifier.weight(1f),
                        )
                        MetricTile(
                            title = "连接数",
                            value =
                                if (state.runtime.traffic.live) {
                                    state.runtime.traffic.connectionCount.toString()
                                } else {
                                    "—"
                                },
                            tone = AppTone.Neutral,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    Text(
                        text =
                            if (running) {
                                "速率由 /connections 累计差分估算；内存来自 /memory（若可用）"
                            } else {
                                "启动连接后显示实时速率、累计流量、曲线与连接数"
                            },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // IP info + exit
            SurfaceCard {
                CardHeader(
                    title = "IP 信息",
                    icon = Icons.Outlined.Public,
                    tone = if (selectedIsIpv6) AppTone.Accent else AppTone.Warning,
                ) {
                    FilledTonalButton(
                        onClick = { onNavigate(AppSection.NODES) },
                        modifier = Modifier.height(34.dp),
                    ) { Text("选择节点") }
                }
                HorizontalDivider(color = colors.surfaceBorder)
                Column(
                    modifier = Modifier.padding(VisualStyle.spacing16),
                    verticalArrangement = Arrangement.spacedBy(VisualStyle.spacing12),
                ) {
                    Text("IPv6 入口", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = if (selectedIsIpv6) state.selectedAddress else "未选择",
                            style =
                                MaterialTheme.typography.bodyLarge.copy(
                                    fontFamily = FontFamily.Monospace,
                                    fontWeight = FontWeight.SemiBold,
                                ),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        if (selectedIsIpv6) {
                            OutlinedButton(onClick = { onCopy("IPv6", state.selectedAddress) }) {
                                Text("复制")
                            }
                        }
                    }
                    // macOS Overview “测试节点” configuration CFST on selected IPv6.
                    val nodeTestRunning =
                        state.speedTest.isRunning && state.speedTest.isNodeTest
                    OutlinedButton(
                        onClick = {
                            if (nodeTestRunning) {
                                onStopSpeedTest()
                            } else {
                                onStartCurrentNodeTest()
                            }
                        },
                        enabled =
                            nodeTestRunning ||
                                (selectedIsIpv6 && !state.speedTest.isRunning),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            when {
                                nodeTestRunning -> "停止测试"
                                state.speedTest.isRunning -> "测速占用中…"
                                else -> "测试节点"
                            },
                        )
                    }
                    if (nodeTestRunning) {
                        Text(
                            state.speedTest.message,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    FilledTonalButton(
                        onClick = onDelayTest,
                        enabled = running && !state.delayTest.isRunning,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            when {
                                state.delayTest.isRunning -> "测试延迟中…"
                                state.delayTest.last?.ok == true ->
                                    "配置延迟 ${state.delayTest.last?.message} · 再测"
                                else -> "测试当前配置延迟"
                            },
                        )
                    }

                    HorizontalDivider(color = colors.surfaceBorder)

                    Text("公网出口", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        text = state.exitIP.info?.ip ?: (state.exitIP.errorMessage ?: "尚未检测"),
                        style =
                            MaterialTheme.typography.bodyLarge.copy(
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.SemiBold,
                            ),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    val loc = state.exitIP.info?.location.orEmpty()
                    val details = state.exitIP.info?.details.orEmpty()
                    if (loc.isNotBlank() || details.isNotBlank()) {
                        Text(
                            listOf(loc, details).filter { it.isNotBlank() }.joinToString(" · "),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        ExitIPDetectionMode.entries.forEach { mode ->
                            val selected = state.exitIP.mode == mode
                            FilledTonalButton(
                                onClick = { onExitIpModeChange(mode) },
                                modifier = Modifier.weight(1f).height(34.dp),
                                colors =
                                    if (selected) {
                                        ButtonDefaults.filledTonalButtonColors(
                                            containerColor = colors.accent.copy(alpha = 0.2f),
                                        )
                                    } else {
                                        ButtonDefaults.filledTonalButtonColors()
                                    },
                            ) { Text(mode.label) }
                        }
                    }
                    Button(
                        onClick = onDetectExitIp,
                        enabled = !state.exitIP.isDetecting,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(if (state.exitIP.isDetecting) "检测中…" else "检测出口 IP")
                    }
                }
            }

            // App info
            SurfaceCard {
                CardHeader(title = "应用信息", icon = Icons.Outlined.Info, tone = AppTone.Neutral)
                HorizontalDivider(color = colors.surfaceBorder)
                CompactInfoRow("版本", BuildConfig.VERSION_NAME, Icons.Outlined.Info)
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "运行",
                    when {
                        !running -> "已停止"
                        state.fullTunnel -> "全量隧道"
                        else -> "HTTP 代理 VPN"
                    },
                    Icons.Outlined.VpnKey,
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("内核", state.runtime.mihomoVersion ?: "mihomo", Icons.Outlined.Timer)
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("代理", "127.0.0.1:${state.runtime.mixedPort}", Icons.Outlined.Route)
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("控制", "127.0.0.1:${state.runtime.controllerPort}", Icons.Outlined.Language)
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("模式", state.routingMode.displayName(), Icons.Outlined.Route)
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "应用路由",
                    when (state.appRouting.mode) {
                        AppRoutingMode.ALL -> "所有应用"
                        AppRoutingMode.BYPASS_SELECTED ->
                            "绕过 ${state.appRouting.selectedCount} 个"
                        AppRoutingMode.ONLY_SELECTED ->
                            "仅代理 ${state.appRouting.selectedCount} 个"
                    },
                    Icons.Outlined.Apps,
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow("VPN MTU", state.vpnMtu, Icons.Outlined.Speed)
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "计费属性",
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        if (state.vpnMetered) "按流量计费" else "不计费"
                    } else {
                        "系统决定"
                    },
                    Icons.Outlined.VpnKey,
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "局域网",
                    if (
                        state.fullTunnel &&
                            state.bypassLocalNetwork &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                    ) {
                        "绕过 VPN"
                    } else {
                        "随 VPN 路由"
                    },
                    Icons.Outlined.Route,
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "IPv6 应用流量",
                    if (state.fullTunnel) state.ipv6RoutingMode.label else "无默认路由",
                    Icons.Outlined.Language,
                )
                HorizontalDivider(color = colors.surfaceBorder, modifier = Modifier.padding(start = 40.dp))
                CompactInfoRow(
                    "DNS",
                    "${state.dnsSettings.mode.label} · ${state.dnsSettings.server}",
                    Icons.Outlined.Language,
                )
                Spacer(Modifier.height(VisualStyle.spacing12))
            }

            Text(
                text = state.statusMessage,
                style = MaterialTheme.typography.bodySmall,
                color =
                    when (state.statusLevel) {
                        LogLevel.Error -> colors.negative
                        LogLevel.Success -> colors.positive
                        LogLevel.Warning -> colors.warning
                        LogLevel.Info -> MaterialTheme.colorScheme.onSurfaceVariant
                    },
                modifier = Modifier.padding(horizontal = VisualStyle.spacing4),
            )
            Spacer(Modifier.height(VisualStyle.spacing8))
        }
    }
}

@Composable
private fun TrafficSparkline(
    points: List<dev.viasix.app.mihomo.SpeedPoint>,
    accent: Color,
    positive: Color,
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier) {
        if (points.size < 2) return@Canvas
        val maxRate =
            points.maxOf { maxOf(it.upBps, it.downBps) }.toFloat().coerceAtLeast(1f)
        val w = size.width
        val h = size.height
        val step = w / (points.size - 1).coerceAtLeast(1)

        fun pathFor(selector: (dev.viasix.app.mihomo.SpeedPoint) -> Long): Path {
            val path = Path()
            points.forEachIndexed { index, point ->
                val x = index * step
                val y = h - (selector(point) / maxRate) * h * 0.9f
                if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            return path
        }

        drawPath(pathFor { it.upBps }, color = accent, style = Stroke(width = 2.5f))
        drawPath(pathFor { it.downBps }, color = positive, style = Stroke(width = 2.5f))
        // baseline
        drawLine(
            color = Color.Gray.copy(alpha = 0.25f),
            start = Offset(0f, h),
            end = Offset(w, h),
            strokeWidth = 1f,
        )
    }
}

@Composable
private fun LinkStep(
    title: String,
    detail: String,
    ready: Boolean,
    active: Boolean,
    actionTitle: String? = null,
    onAction: (() -> Unit)? = null,
) {
    SettingRow(
        title = title,
        detail = detail,
        icon =
            if (active || ready) {
                Icons.Outlined.CheckCircle
            } else {
                Icons.Outlined.RadioButtonUnchecked
            },
    ) {
        if (actionTitle != null && onAction != null) {
            FilledTonalButton(
                onClick = onAction,
                modifier = Modifier.height(32.dp),
                contentPadding = ButtonDefaults.TextButtonContentPadding,
            ) {
                Text(actionTitle, style = MaterialTheme.typography.labelMedium)
            }
        } else {
            StatusBadge(
                title =
                    when {
                        active -> "已启用"
                        ready -> "已就绪"
                        else -> "未就绪"
                    },
                tone =
                    when {
                        active -> AppTone.Positive
                        ready -> AppTone.Accent
                        else -> AppTone.Warning
                    },
            )
        }
    }
}
