# Android 应用

实现位置：[`apps/android`](../../apps/android)。

**状态**：MVP（投影 + VpnService 会话 + 对齐 macOS 的分区 UI）。

## 技术选型

| 项 | 选择 |
| --- | --- |
| UI | Kotlin + Jetpack Compose（Material3 + `ui/theme` 设计令牌） |
| 导航 | 底部栏五分区，对应 macOS `AppSection`（首页 / IPv6 优选 / 连接配置 / 日志 / 设置） |
| 投影 | `:core` JVM 库，contracts 对齐 |
| 虚拟网卡 | `ViaSixVpnService`（`VpnService`） |
| 代理内核 | 预编译 mihomo（assets `mihomo-arm64`，`fetch-mihomo.mjs`） |
| 网络接入 | VpnService 全量路由 + 用户态 TCP/DNS 转发；可选仅 HTTP 代理 |
| 系统代理 | 不支持 |

## 与 macOS 的对应关系

| macOS | Android |
| --- | --- |
| 侧栏导航 | 底部 `NavigationBar` |
| `OverviewView` 链路卡片 | `OverviewScreen` 链路步骤 + 连接/断开 |
| `ProxyRoutingModePicker` | 分段式代理模式选择 |
| 系统代理 + TUN 开关 | 全量隧道开关（平台语义不同） |
| `TrafficStatsView` | 累计上下行（`/connections`） |
| `NodesView` 测速表 | 手动 IPv6 输入（测速后续） |
| `ProfilesView` | YAML 编辑 + 投影预览 |
| `LogsView` | 会话日志环缓冲 |
| `VisualStyle` / `SurfaceCard` | `ui/theme/VisualStyle` + 组件 |

## 验证

```bash
make android-test
make android-skeleton
cd apps/android && gradle :core:test
```

配置与投影行为必须符合 [`contracts/`](../../contracts)。
