package dev.viasix.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import dev.viasix.app.mihomo.ControllerClient
import dev.viasix.app.mihomo.TrafficSample
import dev.viasix.app.prefs.SessionPrefsStore
import dev.viasix.app.state.LogLevel
import dev.viasix.app.state.RuntimeSnapshot
import dev.viasix.app.state.SessionUiState
import dev.viasix.app.state.appendLog
import dev.viasix.app.ui.AppSection
import dev.viasix.app.ui.ViaSixApp
import dev.viasix.app.vpn.ViaSixVpnService
import dev.viasix.core.projection.MihomoProjection
import dev.viasix.core.projection.ProjectError
import dev.viasix.core.projection.ProjectOptions
import dev.viasix.core.projection.RoutingMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private var pendingStart: Intent? = null
    private lateinit var prefsStore: SessionPrefsStore

    private val vpnPermission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == Activity.RESULT_OK) {
                pendingStart?.let { startForegroundService(it) }
            }
            pendingStart = null
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefsStore = SessionPrefsStore(this)
        val initial = SessionUiState.fromPrefs(prefsStore.load())

        setContent {
            var state by remember { mutableStateOf(initial) }
            var selectedSection by remember { mutableStateOf(AppSection.OVERVIEW) }

            fun persist(next: SessionUiState) {
                prefsStore.save(next.toPrefs())
            }

            fun update(transform: (SessionUiState) -> SessionUiState) {
                val next = transform(state)
                state = next
                persist(next)
            }

            LaunchedEffect(Unit) {
                while (true) {
                    val runtimePrefs =
                        getSharedPreferences(
                            ViaSixVpnService.RUNTIME_PREFS,
                            MODE_PRIVATE,
                        )
                    val running = runtimePrefs.getBoolean(ViaSixVpnService.KEY_RUNNING, false)
                    val health =
                        runtimePrefs.getString(ViaSixVpnService.KEY_HEALTH, "—") ?: "—"
                    val port =
                        runtimePrefs.getInt(
                            ViaSixVpnService.KEY_CONTROLLER_PORT,
                            ViaSixVpnService.CONTROLLER_PORT,
                        )
                    val mixed =
                        runtimePrefs.getInt(
                            ViaSixVpnService.KEY_MIXED_PORT,
                            ViaSixVpnService.MIXED_PORT,
                        )
                    val secret =
                        runtimePrefs.getString(ViaSixVpnService.KEY_SECRET, "") ?: ""

                    val traffic =
                        if (running) {
                            withContext(Dispatchers.IO) {
                                ControllerClient.connectionsTotals(
                                    "127.0.0.1",
                                    port,
                                    secret,
                                )
                            }
                        } else {
                            IdleTraffic
                        }

                    // Runtime snapshot does not rewrite session prefs.
                    state =
                        state.copy(
                            runtime =
                                RuntimeSnapshot(
                                    running = running,
                                    health = health,
                                    traffic = traffic,
                                    controllerPort = port,
                                    mixedPort = mixed,
                                ),
                        )
                    kotlinx.coroutines.delay(1500)
                }
            }

            fun buildStartIntent(): Intent =
                Intent(this@MainActivity, ViaSixVpnService::class.java)
                    .putExtra(ViaSixVpnService.EXTRA_PROFILE, state.profileYaml)
                    .putExtra(ViaSixVpnService.EXTRA_SELECTED_IP, state.selectedAddress)
                    .putExtra(ViaSixVpnService.EXTRA_MODE, state.routingMode.wire)
                    .putExtra(ViaSixVpnService.EXTRA_FULL_TUNNEL, state.fullTunnel)

            fun startVpn() {
                val intent = buildStartIntent()
                val prepare = VpnService.prepare(this@MainActivity)
                if (prepare != null) {
                    pendingStart = intent
                    vpnPermission.launch(prepare)
                    update { it.appendLog("请求 VPN 权限…", LogLevel.Info) }
                } else {
                    startForegroundService(intent)
                    update { it.appendLog("正在启动 VPN + mihomo…", LogLevel.Info) }
                }
            }

            fun stopVpn() {
                startService(
                    Intent(this@MainActivity, ViaSixVpnService::class.java)
                        .setAction(ViaSixVpnService.ACTION_STOP),
                )
                update { it.appendLog("已发送停止意图", LogLevel.Info) }
            }

            fun projectPreview() {
                try {
                    val preview =
                        MihomoProjection.projectYaml(
                            if (state.routingMode == RoutingMode.DIRECT) {
                                null
                            } else {
                                state.profileYaml
                            },
                            ProjectOptions(
                                routingMode = state.routingMode,
                                selectedAddress =
                                    if (state.routingMode == RoutingMode.DIRECT) {
                                        null
                                    } else {
                                        state.selectedAddress
                                    },
                            ),
                        )
                    update {
                        it.copy(configPreview = preview)
                            .appendLog("投影成功", LogLevel.Success)
                    }
                } catch (error: ProjectError) {
                    update {
                        it.copy(configPreview = error.contractCode)
                            .appendLog("投影失败：${error.contractCode}", LogLevel.Error)
                    }
                } catch (error: Exception) {
                    update {
                        it.copy(configPreview = error.message ?: "error")
                            .appendLog("投影失败：${error.message}", LogLevel.Error)
                    }
                }
            }

            ViaSixApp(
                state = state,
                selectedSection = selectedSection,
                onSectionChange = { selectedSection = it },
                onProfileChange = { yaml -> update { it.copy(profileYaml = yaml) } },
                onSelectedAddressChange = { ip -> update { it.copy(selectedAddress = ip) } },
                onRoutingModeChange = { mode -> update { it.copy(routingMode = mode) } },
                onFullTunnelChange = { full -> update { it.copy(fullTunnel = full) } },
                onStart = ::startVpn,
                onStop = ::stopVpn,
                onProjectPreview = ::projectPreview,
                onClearLogs = {
                    state = state.copy(logs = emptyList(), statusMessage = "日志已清空")
                },
            )
        }
    }
}

/** Idle traffic sample without hitting the controller. */
private val IdleTraffic =
    TrafficSample(
        live = false,
        message = "—",
        uploadTotal = 0,
        downloadTotal = 0,
    )
