package dev.viasix.app.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.ui.screens.LogsScreen
import dev.viasix.app.ui.screens.NodesScreen
import dev.viasix.app.ui.screens.OverviewScreen
import dev.viasix.app.ui.screens.ProfilesScreen
import dev.viasix.app.ui.screens.SettingsScreen
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.ViaSixTheme
import dev.viasix.core.projection.RoutingMode

@Composable
fun ViaSixApp(
    state: SessionUiState,
    selectedSection: AppSection,
    onSectionChange: (AppSection) -> Unit,
    onProfileChange: (String) -> Unit,
    onSelectedAddressChange: (String) -> Unit,
    onRoutingModeChange: (RoutingMode) -> Unit,
    onFullTunnelChange: (Boolean) -> Unit,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onProjectPreview: () -> Unit,
    onClearLogs: () -> Unit,
) {
    ViaSixTheme {
        val colors = LocalViaSixColors.current
        Scaffold(
            containerColor = colors.pageBackground,
            bottomBar = {
                NavigationBar(
                    containerColor = colors.surface,
                    contentColor = colors.accent,
                ) {
                    AppSection.entries.forEach { section ->
                        val selected = selectedSection == section
                        NavigationBarItem(
                            selected = selected,
                            onClick = { onSectionChange(section) },
                            icon = {
                                Icon(
                                    imageVector = section.icon,
                                    contentDescription = section.title,
                                )
                            },
                            label = {
                                Text(
                                    text = section.title,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            },
                            colors =
                                NavigationBarItemDefaults.colors(
                                    selectedIconColor = colors.accent,
                                    selectedTextColor = colors.accent,
                                    indicatorColor = colors.accent.copy(alpha = 0.14f),
                                ),
                        )
                    }
                }
            },
        ) { padding ->
            androidx.compose.foundation.layout.Box(
                modifier = Modifier.padding(padding),
            ) {
                when (selectedSection) {
                    AppSection.OVERVIEW ->
                        OverviewScreen(
                            state = state,
                            onRoutingModeChange = onRoutingModeChange,
                            onFullTunnelChange = onFullTunnelChange,
                            onStart = onStart,
                            onStop = onStop,
                            onNavigate = onSectionChange,
                        )
                    AppSection.NODES ->
                        NodesScreen(
                            state = state,
                            onSelectedAddressChange = onSelectedAddressChange,
                        )
                    AppSection.PROFILES ->
                        ProfilesScreen(
                            state = state,
                            onProfileChange = onProfileChange,
                            onProjectPreview = onProjectPreview,
                        )
                    AppSection.LOGS ->
                        LogsScreen(
                            state = state,
                            onClear = onClearLogs,
                        )
                    AppSection.SETTINGS ->
                        SettingsScreen(
                            state = state,
                            onFullTunnelChange = onFullTunnelChange,
                        )
                }
            }
        }
    }
}
