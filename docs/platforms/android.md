# Android 应用

实现位置：[`apps/android`](../../apps/android)。

ViaSix **全平台**产品中的 Android 端（移动网络接入语义与桌面不同：无系统代理，以 VpnService 为主）。

**状态**：MVP（投影 + VpnService 会话 + 对齐桌面的分区 UI）。

## 技术选型

| 项 | 选择 |
| --- | --- |
| UI | Kotlin + Jetpack Compose（Material3 + `ui/theme` 设计令牌） |
| 导航 | 底部栏五分区，对应 macOS `AppSection`（首页 / IPv6 优选 / 连接配置 / 日志 / 设置） |
| 投影 | `:core` JVM 库，contracts 对齐 |
| 虚拟网卡 | `ViaSixVpnService`（`VpnService`） |
| 代理内核 | 预编译 mihomo（assets `mihomo-arm64`，`fetch-mihomo.mjs`） |
| 测速 | CloudflareSpeedTest arm64（assets `cfst-arm64`，`fetch-cfst.mjs`；linux_arm64 上游） |
| 网络接入 | VpnService 全量路由 + 用户态 TCP/DNS 转发；可选仅 HTTP 代理 |
| 系统代理 | 不支持 |

## 与 macOS 的对应关系（权威对齐目标）

Android 功能对齐以 **macOS** 为准。Windows 端仍在完善中，**不得**作为 Android 行为的参照源。


| macOS | Android |
| --- | --- |
| 侧栏导航 | 底部 `NavigationBar` |
| `OverviewView` 链路卡片 | `OverviewScreen` 链路步骤 + 连接/断开 |
| `ProxyRoutingModePicker` | 分段式代理模式；运行中 `PATCH /configs` |
| 系统代理 + TUN 开关 | 全量隧道开关（平台语义不同） |
| `TrafficStatsView` | 速率（累计差分）+ 曲线 + 内存 + 连接数 |
| 出口 IP 检测 | `ExitIPDetector`（端点/模式/地理 enrichment 对齐） |
| 配置延迟测试 | `ControllerClient.proxyDelay` |
| `NodesView` / CFST | IPv6 校验、候选库、IP 源、参数校验与面板、起停、结果排序、当前节点测速、应用/应用并重连 |
| Overview「测试节点」 | 首页对选中 IPv6 的配置测速（macOS configuration test） |
| `ProfilesView` | 摘要解析、文件导入、YAML 编辑、投影预览 |
| `LogsView` | 来源/级别过滤、搜索、排序 + VPN 事件合并 |
| `VisualStyle` / `SurfaceCard` | `ui/theme/VisualStyle` + 组件 |

## 加固要点

- `TrafficSampler`：与 Windows 相同，由 `/connections` 累计差分得瞬时速率
- `ViaSixVpnService`：重启栈（节点应用并重连）、环形事件日志
- `ProfileSummaryParser` / `Ipv6Address` / `ByteRateFormatter` / `SpeedTestResultParser`：`:core` 可测纯逻辑
- 会话偏好扩展：候选节点、出口检测端点与模式、测速 IP 源
- CFST：`CfstInstaller` + `CfstRunner` + `IPSourceMode` / `SpeedTestParameters`（macOS 参数语义）+ `NodeResultSorting` + 当前节点测速

## 验证

```bash
make android-test
make android-skeleton
cd apps/android && gradle :core:test
```

配置与投影行为必须符合 [`contracts/`](../../contracts)。
