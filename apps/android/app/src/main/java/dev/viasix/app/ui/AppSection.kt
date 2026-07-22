package dev.viasix.app.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * Primary navigation sections, aligned with macOS [AppSection].
 * Mobile uses a bottom bar instead of a sidebar.
 */
enum class AppSection(
    val title: String,
    val subtitle: String,
    val icon: ImageVector,
) {
    OVERVIEW(
        title = "首页",
        subtitle = "IPv6 链路状态与控制",
        icon = Icons.Outlined.Home,
    ),
    NODES(
        title = "IPv6 优选",
        subtitle = "测速并选择 IPv6 地址",
        icon = Icons.Outlined.Hub,
    ),
    PROFILES(
        title = "连接配置",
        subtitle = "管理 IPv6 代理入口配置",
        icon = Icons.Outlined.Inventory2,
    ),
    LOGS(
        title = "日志",
        subtitle = "查看代理与会话活动",
        icon = Icons.AutoMirrored.Outlined.Article,
    ),
    SETTINGS(
        title = "设置",
        subtitle = "网络接入与应用信息",
        icon = Icons.Outlined.Settings,
    ),
}
