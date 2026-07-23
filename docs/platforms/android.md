# Android 应用

实现位置：[`apps/android`](../../apps/android)。

ViaSix **全平台**产品中的 Android 端（移动网络接入语义与桌面不同：无系统代理，以 VpnService 为主）。

**状态**：生产可用（对齐 macOS 五分区工作流 + 全量隧道 TCP/UDP IPv4/IPv6）。平台差异见下表；可选增强（native hev 等）见 [roadmap 阶段 2](../architecture/roadmap.md)。

## 技术选型

| 项 | 选择 |
| --- | --- |
| UI | Kotlin + Jetpack Compose（Material3 + `ui/theme` 设计令牌） |
| 导航 | 自适应五分区：手机底部栏、横屏/折叠屏导航轨、平板上下文侧栏，对应 macOS `AppSection` |
| 投影 | `:core` JVM 库，contracts 对齐 |
| 虚拟网卡 | `ViaSixVpnService`（`VpnService`） |
| 代理内核 | 预编译 mihomo（assets `mihomo-arm64`，`fetch-mihomo.mjs`） |
| 测速 | CloudflareSpeedTest arm64（assets `cfst-arm64`，`fetch-cfst.mjs`；linux_arm64 上游） |
| 网络接入 | VpnService 全量路由 + 用户态 TCP/UDP（SOCKS5 CONNECT / UDP ASSOCIATE）；可选仅 HTTP 代理 |
| 系统代理 | 不支持 |

## 与 macOS 的对应关系（权威对齐目标）

Android 功能对齐以 **macOS** 为准。Windows 端仍在完善中，**不得**作为 Android 行为的参照源。


| macOS | Android |
| --- | --- |
| 侧栏导航 | 自适应 `NavigationBar` / `NavigationRail` / 上下文侧栏 |
| `OverviewView` 链路卡片 | `OverviewScreen` 链路步骤 + 连接/断开 |
| `ProxyRoutingModePicker` | 分段式代理模式；运行中 `PATCH /configs` |
| 系统代理 + TUN 开关 | 全量隧道开关（平台语义不同） |
| `TrafficStatsView` | 速率（累计差分）+ 曲线 + 内存 + 连接数 |
| 出口 IP 检测 | `ExitIPDetector`（端点/模式/地理 enrichment 对齐） |
| 配置延迟测试 | `ControllerClient.proxyDelay` |
| `NodesView` / CFST | IPv6 校验、候选库、IP 源、参数校验与面板、起停、结果排序、当前节点测速、应用/应用并重连 |
| Overview「测试节点」 | 首页对选中 IPv6 的配置测速（macOS configuration test） |
| `ProfilesView` | 摘要解析、文件/剪贴板导入、安全 YAML 草稿、校验后应用/还原、运行中应用并重连、投影预览 |
| `LogsView` | 来源/级别过滤、搜索、排序 + VPN 事件合并 |
| `VisualStyle` / `SurfaceCard` | `ui/theme/VisualStyle` + 组件 |
| XPC helper + utun | `VpnService` + 用户态 `Tun2SocksEngine`（无独立特权 helper） |
| 菜单栏 | 不适用 |

## 加固要点

- `TrafficSampler`：与 Windows 相同，由 `/connections` 累计差分得瞬时速率
- `ViaSixVpnService`：重启栈（节点应用并重连）、环形事件日志、通知栏实时上下行（Clash 风格）
- `ViaSixTileService`：API 34+ 通过 `PendingIntent` 展开应用，API 26–28 不访问 API 29 的磁贴字幕
- 通知权限：Android 13+ 首次连接前按需请求；拒绝后会话降级运行且不自动重复询问，设置页提供再次请求/系统设置入口
- 会话恢复：持久化当前主分区；Activity 旋转/进程重建时从 VPN runtime 快照同步恢复，授权中的连接动作通过 saved state 延续
- 运行态监督：runtime 快照绑定当前应用进程，拒绝跨重启残留的 `running=true`；Sticky 服务以已保存配置恢复，mihomo/TUN 异常退出或系统撤销 VPN 权限时自动清理会话
- 系统 VPN 控制：设置页显示真实授权状态，可独立发起系统授权；授权后直达 Android VPN 设置以管理“始终开启 VPN”等系统行为，Always-on/Sticky 系统启动均恢复已保存会话，返回应用自动刷新状态
- 后台稳定性：设置页读取系统电池优化状态并提供设置入口，帮助长期 VPN/Always-on 会话避免被 OEM 后台策略回收；不声明直接请求豁免的敏感权限
- 数据重置安全：VPN 启动中、运行中或停止中均禁止清除会话偏好，避免当前连接与 Sticky/Always-on 后续恢复参数分叉
- 组件完整性：本地 mihomo / CFST 检查 64-bit little-endian AArch64 ELF、架构与执行权限；设置页区分缺失/损坏并可独立原子修复
- 本地数据保护：保持 `allowBackup=false`，并为 Android 12+ 数据提取与旧版 Auto Backup 显式排除全部私有域，防止配置 YAML、候选节点、控制器密钥和运行状态进入云备份或设备迁移
- `ProfileSummaryParser` / `Ipv6Address` / `ByteRateFormatter` / `SpeedTestResultParser`：`:core` 可测纯逻辑
- 会话偏好扩展：候选节点、出口检测端点与模式、测速 IP 源
- 配置安全编辑：`profileDraft` 与已应用 `profileYaml` 分离持久化；应用前检查 `x-viasix` 并执行真实投影校验
- CFST：`CfstInstaller` + `CfstRunner` + `IPSourceMode` / `SpeedTestParameters`（macOS 参数语义）+ `NodeResultSorting` + 当前节点测速
- 全量隧道：`Tun2SocksEngine` — IPv4/IPv6 TCP→SOCKS5 CONNECT；通用 UDP→**每本地源端口** SOCKS5 UDP ASSOCIATE（正确并发 demux）；DNS 默认经同一 SOCKS 路径，也可显式切换为 per-query `protect` 直连并自定义数字 IPv4/IPv6 服务器
- VPN MTU：设置页可在与 macOS 一致的 1280–9000 安全范围内调整，默认 1500；参数随 Activity、磁贴与 Sticky/Always-on 系统恢复统一传递
- VPN 计费属性：Android 10+ 可选择保持默认“按流量计费”或标记为不计费；仅影响系统后台数据策略，不改变物理网络资费，运行中锁定修改
- 局域网绕过：Android 13+ 使用原生 `VpnService.Builder.excludeRoute` 排除 IPv4/IPv6 私网、回环、链路本地、组播与广播目标；默认关闭，所选 DNS 以更具体的 VPN 主机路由保留，系统锁定 VPN 仍可能阻止其他隧道外访问
- IPv6 应用流量：全量隧道支持“经 VPN / 阻止 / 绕过 VPN”三态；默认经 VPN，IPv6 地址或默认路由建立失败时中止会话而不是静默旁路；阻止/绕过模式要求 IPv4 DNS，绕过模式会暴露设备真实 IPv6；HTTP 代理-only 模式显式允许 IPv6 地址族，不会因无 IPv6 VPN 路由而误阻断
- 分应用路由：支持所有应用、绕过所选和仅代理所选三种 `VpnService.Builder` 策略；选择器仅查询具有 Launcher 入口的应用，后台型应用可手动添加包名，不申请广泛包可见权限，运行中锁定修改

## 移动端交互（参考 Clash Meta / NekoBox，语义仍对齐 macOS）

| 能力 | 说明 |
| --- | --- |
| 首页大连接控制 | Overview 顶部连接/断开 + 实时速率条（类似 Clash 电源按钮） |
| 快捷设置磁贴 | `ViaSixTileService` 一键启停；与应用共用 `SessionStartGate` |
| 配置粘贴导入 | Profiles「粘贴剪贴板」识别 mihomo/Clash YAML（不自动拉订阅 URL） |
| 通知实时流量与控制 | 前台 VPN 通知展示 ↑/↓ 紧凑速率与连接数，并提供“断开”动作；更新不重复提醒 |
| 通知权限体验 | Android 13+ 仅在首次连接前询问；快捷磁贴会转入应用完成授权，拒绝不阻塞 VPN |
| 会话恢复与回流 | 重建后立即恢复当前分区/运行态；磁贴和通知通过 `CLEAR_TOP + SINGLE_TOP` 回到既有 Activity 并处理新意图 |
| 运行组件管理 | 启动时只读检查，设置页分别安装/修复/重装 mihomo 与 CFST；VPN 或测速运行中禁止替换对应组件 |
| 自适应应用壳 | `<600dp` 底部栏、`600–839dp` 导航轨、`≥840dp` 带连接状态和当前 IPv6 的侧栏 |
| 跨端品牌图标 | 启动器复用 macOS IPv6 地址标记，支持 Adaptive Icon、圆形蒙版和 Android 13 主题图标；磁贴/通知使用高对比紧凑标记 |

## 验证

```bash
make android-test
make android-skeleton
make android-assemble   # 需 Android SDK
cd apps/android && gradle :core:test :app:test
```

配置与投影行为必须符合 [`contracts/`](../../contracts)。
