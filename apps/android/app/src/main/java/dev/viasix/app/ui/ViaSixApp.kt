package dev.viasix.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import dev.viasix.app.net.ExitIPDetectionMode
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.ui.screens.LogsScreen
import dev.viasix.app.ui.screens.NodesScreen
import dev.viasix.app.ui.screens.OverviewScreen
import dev.viasix.app.ui.screens.ProfilesScreen
import dev.viasix.app.ui.screens.SettingsScreen
import dev.viasix.app.ui.theme.LocalViaSixColors
import dev.viasix.app.ui.theme.ViaSixTheme
import dev.viasix.core.projection.RoutingMode
import dev.viasix.core.speedtest.IPSourceMode
import dev.viasix.core.speedtest.NodeSortKey
import dev.viasix.core.speedtest.SpeedTestParameters

@Composable
fun ViaSixApp(
    state: SessionUiState,
    selectedSection: AppSection,
    onSectionChange: (AppSection) -> Unit,
    onProfileChange: (String) -> Unit,
    onImportProfile: () -> Unit,
    onSelectedAddressChange: (String) -> Unit,
    onApplyNode: (address: String, reconnect: Boolean) -> Unit,
    onRemoveCandidate: (String) -> Unit,
    onSpeedParametersChange: (SpeedTestParameters) -> Unit = {},
    onIpSourceModeChange: (IPSourceMode) -> Unit = {},
    onCustomIpFilePathChange: (String) -> Unit = {},
    onResetSpeedParameters: () -> Unit = {},
    onToggleParametersExpanded: () -> Unit = {},
    onStartSpeedTest: () -> Unit = {},
    onStopSpeedTest: () -> Unit = {},
    onStartCurrentNodeTest: () -> Unit = {},
    onSpeedSortChange: (NodeSortKey) -> Unit = {},
    onRefreshCfstStatus: () -> Unit = {},
    onRoutingModeChange: (RoutingMode) -> Unit,
    onFullTunnelChange: (Boolean) -> Unit,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onProjectPreview: () -> Unit,
    onDetectExitIp: () -> Unit,
    onExitIpModeChange: (ExitIPDetectionMode) -> Unit,
    onExitIpEndpointChange: (String) -> Unit,
    onDelayTest: () -> Unit,
    onCopy: (label: String, value: String) -> Unit,
    onClearLogs: () -> Unit,
    onDismissNotice: () -> Unit,
    onClearSessionData: () -> Unit,
) {
    ViaSixTheme {
        val colors = LocalViaSixColors.current
        val snackbarHostState = remember { SnackbarHostState() }

        LaunchedEffect(state.notice?.id) {
            val notice = state.notice ?: return@LaunchedEffect
            val result =
                snackbarHostState.showSnackbar(
                    message = notice.message,
                    actionLabel = if (notice.actionOpenSettings) "设置" else null,
                    withDismissAction = true,
                )
            if (result == androidx.compose.material3.SnackbarResult.ActionPerformed &&
                notice.actionOpenSettings
            ) {
                onSectionChange(AppSection.SETTINGS)
            }
            onDismissNotice()
        }

        Scaffold(
            containerColor = colors.pageBackground,
            snackbarHost = { SnackbarHost(snackbarHostState) },
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
            Box(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(padding),
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
                            onDetectExitIp = onDetectExitIp,
                            onExitIpModeChange = onExitIpModeChange,
                            onDelayTest = onDelayTest,
                            onCopy = onCopy,
                            onStartCurrentNodeTest = onStartCurrentNodeTest,
                            onStopSpeedTest = onStopSpeedTest,
                        )
                    AppSection.NODES ->
                        NodesScreen(
                            state = state,
                            onSelectedAddressChange = onSelectedAddressChange,
                            onApplyNode = onApplyNode,
                            onRemoveCandidate = onRemoveCandidate,
                            onCopy = onCopy,
                            onSpeedParametersChange = onSpeedParametersChange,
                            onIpSourceModeChange = onIpSourceModeChange,
                            onCustomIpFilePathChange = onCustomIpFilePathChange,
                            onResetSpeedParameters = onResetSpeedParameters,
                            onToggleParametersExpanded = onToggleParametersExpanded,
                            onStartSpeedTest = onStartSpeedTest,
                            onStopSpeedTest = onStopSpeedTest,
                            onStartCurrentNodeTest = onStartCurrentNodeTest,
                            onSpeedSortChange = onSpeedSortChange,
                        )
                    AppSection.PROFILES ->
                        ProfilesScreen(
                            state = state,
                            onProfileChange = onProfileChange,
                            onProjectPreview = onProjectPreview,
                            onImportProfile = onImportProfile,
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
                            onExitIpModeChange = onExitIpModeChange,
                            onExitIpEndpointChange = onExitIpEndpointChange,
                            onDetectExitIp = onDetectExitIp,
                            onClearSessionData = onClearSessionData,
                            onRefreshCfstStatus = onRefreshCfstStatus,
                        )
                }
            }
        }
    }
}
