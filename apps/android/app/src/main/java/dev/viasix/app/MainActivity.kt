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
    private val vpnPermission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode == Activity.RESULT_OK) {
                startService(Intent(this, ViaSixVpnService::class.java))
            }
        }

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
                    var preview by remember { mutableStateOf("# 点击生成运行配置") }
                    var status by remember { mutableStateOf("Android MVP · VpnService 骨架") }

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
                            "IPv6-first · contracts 投影 · VpnService（TUN 语义）",
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
                        Button(
                            onClick = {
                                try {
                                    preview =
                                        MihomoProjection.projectYaml(
                                            profile,
                                            ProjectOptions(
                                                routingMode = RoutingMode.RULE,
                                                selectedAddress = selectedIp,
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
                                val prepare = VpnService.prepare(this@MainActivity)
                                if (prepare != null) {
                                    vpnPermission.launch(prepare)
                                    status = "请求 VPN 权限…"
                                } else {
                                    startService(Intent(this@MainActivity, ViaSixVpnService::class.java))
                                    status = "VpnService 已请求启动（骨架，尚未嵌入 mihomo）"
                                }
                            },
                        ) {
                            Text("请求 VPN / 启动服务骨架")
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
                            Text("停止 VPN 服务")
                        }
                        Text(status, style = MaterialTheme.typography.bodySmall)
                        Text(preview, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}
