package dev.viasix.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.Row
import androidx.compose.ui.Alignment
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.viasix.app.mihomo.ControllerClient
import dev.viasix.app.prefs.SessionPrefs
import dev.viasix.app.prefs.SessionPrefsStore
import dev.viasix.app.vpn.ViaSixVpnService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import dev.viasix.core.projection.MihomoProjection
import dev.viasix.core.projection.ProjectError
import dev.viasix.core.projection.ProjectOptions
import dev.viasix.core.projection.RoutingMode

class MainActivity : ComponentActivity() {
    private var pendingStart: Intent? = null
    private lateinit var prefsStore: SessionPrefsStore

    private val vpnPermission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == Activity.RESULT_OK) {
                pendingStart?.let { startForegroundServiceCompat(it) }
            }
            pendingStart = null
        }

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefsStore = SessionPrefsStore(this)
        val initial = prefsStore.load()
        val defaultProfile =
            """
            proxies:
              - name: My VLESS
                type: vless
                server: origin.example.com
                port: 443
                uuid: 11111111-1111-4111-1111-111111111111
            x-viasix:
              version: 1
              primary-server: selected-ip
            """.trimIndent()

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    var profile by remember {
                        mutableStateOf(
                            initial.profileYaml.ifBlank { defaultProfile },
                        )
                    }
                    var selectedIp by remember {
                        mutableStateOf(initial.selectedAddress.ifBlank { "2001:db8::1" })
                    }
                    var mode by remember {
                        mutableStateOf(RoutingMode.parse(initial.routingMode) ?: RoutingMode.RULE)
                    }
                    var modeExpanded by remember { mutableStateOf(false) }
                    var fullTunnel by remember { mutableStateOf(initial.fullTunnel) }
                    var preview by remember { mutableStateOf("# 点击生成运行配置") }
                    var status by remember {
                        mutableStateOf("Android · 投影 + mihomo + 全量隧道(TCP/DNS)")
                    }
                    var runtimeLine by remember { mutableStateOf("运行时：—") }

                    fun persist() {
                        prefsStore.save(
                            SessionPrefs(
                                profileYaml = profile,
                                selectedAddress = selectedIp,
                                routingMode = mode.wire,
                                fullTunnel = fullTunnel,
                            ),
                        )
                    }

                    LaunchedEffect(profile, selectedIp, mode, fullTunnel) {
                        persist()
                    }

                    LaunchedEffect(Unit) {
                        while (true) {
                            val runtime =
                                getSharedPreferences(
                                    ViaSixVpnService.RUNTIME_PREFS,
                                    MODE_PRIVATE,
                                )
                            val running = runtime.getBoolean(ViaSixVpnService.KEY_RUNNING, false)
                            val health =
                                runtime.getString(ViaSixVpnService.KEY_HEALTH, "—") ?: "—"
                            if (!running) {
                                runtimeLine = "运行时：已停止"
                            } else {
                                val port =
                                    runtime.getInt(
                                        ViaSixVpnService.KEY_CONTROLLER_PORT,
                                        ViaSixVpnService.CONTROLLER_PORT,
                                    )
                                val secret =
                                    runtime.getString(ViaSixVpnService.KEY_SECRET, "") ?: ""
                                val traffic =
                                    withContext(Dispatchers.IO) {
                                        ControllerClient.connectionsTotals(
                                            "127.0.0.1",
                                            port,
                                            secret,
                                        )
                                    }
                                runtimeLine =
                                    if (traffic.live) {
                                        "运行时：$health · ${traffic.message}"
                                    } else {
                                        "运行时：$health · ${traffic.message}"
                                    }
                            }
                            kotlinx.coroutines.delay(1500)
                        }
                    }

                    fun buildStartIntent(): Intent =
                        Intent(this@MainActivity, ViaSixVpnService::class.java)
                            .putExtra(ViaSixVpnService.EXTRA_PROFILE, profile)
                            .putExtra(ViaSixVpnService.EXTRA_SELECTED_IP, selectedIp)
                            .putExtra(ViaSixVpnService.EXTRA_MODE, mode.wire)
                            .putExtra(ViaSixVpnService.EXTRA_FULL_TUNNEL, fullTunnel)

                    Column(
                        modifier =
                            Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text("ViaSix", style = MaterialTheme.typography.headlineMedium)
                        Text(
                            "IPv6-first · contracts 投影 · mihomo · VpnService HTTP 代理",
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        OutlinedTextField(
                            value = profile,
                            onValueChange = {
                                profile = it
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Profile YAML") },
                            minLines = 8,
                        )
                        OutlinedTextField(
                            value = selectedIp,
                            onValueChange = {
                                selectedIp = it
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("选中 IPv6") },
                            singleLine = true,
                        )
                        ExposedDropdownMenuBox(
                            expanded = modeExpanded,
                            onExpandedChange = { modeExpanded = it },
                        ) {
                            OutlinedTextField(
                                value = mode.wire,
                                onValueChange = {},
                                readOnly = true,
                                label = { Text("路由模式") },
                                trailingIcon = {
                                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = modeExpanded)
                                },
                                modifier =
                                    Modifier
                                        .menuAnchor()
                                        .fillMaxWidth(),
                            )
                            ExposedDropdownMenu(
                                expanded = modeExpanded,
                                onDismissRequest = { modeExpanded = false },
                            ) {
                                RoutingMode.entries.forEach { item ->
                                    DropdownMenuItem(
                                        text = { Text(item.wire) },
                                        onClick = {
                                            mode = item
                                            modeExpanded = false
                                        },
                                    )
                                }
                            }
                        }
                        Button(
                            onClick = {
                                try {
                                    preview =
                                        MihomoProjection.projectYaml(
                                            if (mode == RoutingMode.DIRECT) null else profile,
                                            ProjectOptions(
                                                routingMode = mode,
                                                selectedAddress =
                                                    if (mode == RoutingMode.DIRECT) {
                                                        null
                                                    } else {
                                                        selectedIp
                                                    },
                                            ),
                                        )
                                    status = "投影成功"
                                } catch (error: ProjectError) {
                                    preview = error.contractCode
                                    status = "投影失败：${error.contractCode}"
                                } catch (error: Exception) {
                                    preview = error.message ?: "error"
                                    status = "投影失败"
                                }
                            },
                        ) {
                            Text("生成运行配置")
                        }
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Switch(checked = fullTunnel, onCheckedChange = { fullTunnel = it })
                            Text(
                                if (fullTunnel) {
                                    "全量隧道（IPv4 TCP→SOCKS + DNS）"
                                } else {
                                    "仅 HTTP 代理 VPN（无默认路由）"
                                },
                            )
                        }
                        Button(
                            onClick = {
                                val intent = buildStartIntent()
                                val prepare = VpnService.prepare(this@MainActivity)
                                if (prepare != null) {
                                    pendingStart = intent
                                    vpnPermission.launch(prepare)
                                    status = "请求 VPN 权限…"
                                } else {
                                    startForegroundServiceCompat(intent)
                                    status = "正在启动 VPN + mihomo…"
                                }
                            },
                        ) {
                            Text("启动（VPN + mihomo）")
                        }
                        Button(
                            onClick = {
                                startService(
                                    Intent(this@MainActivity, ViaSixVpnService::class.java)
                                        .setAction(ViaSixVpnService.ACTION_STOP),
                                )
                                status = "已发送停止意图"
                            },
                        ) {
                            Text("停止")
                        }
                        Text(status, style = MaterialTheme.typography.bodySmall)
                        Text(runtimeLine, style = MaterialTheme.typography.bodySmall)
                        Text(
                            "全量隧道：默认路由 + 用户态转发（TCP via mihomo SOCKS，DNS protect 出站）。" +
                                "本应用 UID 排除在 VPN 外以防环路。需 arm64 + fetch-mihomo.mjs。",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Text(preview, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }

    private fun startForegroundServiceCompat(intent: Intent) {
        startForegroundService(intent)
    }
}
