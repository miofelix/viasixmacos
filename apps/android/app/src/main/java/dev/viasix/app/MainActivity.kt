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
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.viasix.app.vpn.ViaSixVpnService
import dev.viasix.core.projection.MihomoProjection
import dev.viasix.core.projection.ProjectError
import dev.viasix.core.projection.ProjectOptions
import dev.viasix.core.projection.RoutingMode

class MainActivity : ComponentActivity() {
    private var pendingStart: Intent? = null

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
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    var profile by remember {
                        mutableStateOf(
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
                            """.trimIndent(),
                        )
                    }
                    var selectedIp by remember { mutableStateOf("2001:db8::1") }
                    var mode by remember { mutableStateOf(RoutingMode.RULE) }
                    var modeExpanded by remember { mutableStateOf(false) }
                    var preview by remember { mutableStateOf("# 点击生成运行配置") }
                    var status by remember {
                        mutableStateOf("Android · 投影 + mihomo 用户态 + VPN HTTP 代理")
                    }

                    fun buildStartIntent(): Intent =
                        Intent(this@MainActivity, ViaSixVpnService::class.java)
                            .putExtra(ViaSixVpnService.EXTRA_PROFILE, profile)
                            .putExtra(ViaSixVpnService.EXTRA_SELECTED_IP, selectedIp)
                            .putExtra(ViaSixVpnService.EXTRA_MODE, mode.wire)

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
                            onValueChange = { profile = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Profile YAML") },
                            minLines = 8,
                        )
                        OutlinedTextField(
                            value = selectedIp,
                            onValueChange = { selectedIp = it },
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
                        Text(
                            "说明：当前通过 VpnService.setHttpProxy 发布 mixed 代理；" +
                                "未做 0.0.0.0/0 全量路由，避免未接 TUN 时断网。需先 node scripts/fetch-mihomo.mjs。",
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
