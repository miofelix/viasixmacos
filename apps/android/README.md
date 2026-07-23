# ViaSix for Android

ViaSix **全平台**产品中的 Android 端。跨端总览见根 [README](../../README.md)。

**状态：生产可用**（contracts 投影 + VpnService 全量隧道 TCP/UDP IPv4/IPv6 + 五分区 UI，对齐 macOS 语义；无系统代理 / 无菜单栏为平台差异）

## 模块

| 模块 | 说明 |
| --- | --- |
| `:core` | 纯 JVM：Mihomo 投影，对齐 monorepo contracts fixtures |
| `:app` | Compose UI + `ViaSixVpnService` + 用户态 `Tun2SocksEngine` |

## 要求

- JDK 17+
- Android SDK（组装 APK 时）
- Gradle（本机 `gradle` 或后续 wrapper）

## 命令

```bash
cd apps/android
gradle :core:test            # contracts + CFST 解析/参数
gradle :app:test             # app 单元测试（CFST、隧道 framing/NAT/包编解码等）
gradle :app:assembleDebug    # 生成 debug APK（需 Android SDK）
node scripts/fetch-mihomo.mjs  # 可选：下载 arm64 mihomo 到 assets
node scripts/fetch-cfst.mjs    # 可选：下载 arm64 CFST 到 assets（IPv6 优选）
```

仓库根：

```bash
make android-test
make android-skeleton
make android-assemble
```

## UI 结构（对齐 macOS）

自适应导航对应桌面端侧栏 `AppSection`：手机使用底部栏，横屏/折叠屏使用导航轨，平板和桌面窗口使用带连接上下文的侧栏。

| 分区 | 说明 |
| --- | --- |
| 首页 | IPv6 链路步骤、代理模式、网络接入、流量、IP / 应用信息 |
| IPv6 优选 | CFST 测速、结果表、应用 / 应用并重连 + 手动入口 |
| 连接配置 | Profile YAML 安全草稿、校验后应用/还原、运行中应用并重连 + 投影预览 |
| 日志 | 会话活动时间线 |
| 设置 | 全量隧道开关、运行组件、关于 |

设计令牌与卡片组件见 `ui/theme/`（对应 macOS `VisualStyle` / `SurfaceCard` 等）。

## 当前范围

| 能力 | 状态 |
| --- | --- |
| contracts 投影 | ✓（`:core` 测试） |
| 分区导航 UI（对齐 macOS 信息架构） | ✓ |
| VpnService 权限与前台会话 / 重启重连 | ✓ |
| mihomo 用户态启动（assets → filesDir） | ✓ |
| 全量隧道 IPv4/IPv6 TCP→SOCKS | ✓（`Tun2SocksEngine`） |
| 全量隧道通用 UDP→SOCKS5 UDP ASSOCIATE | ✓（每本地源端口一条 ASSOCIATE；DNS/53 独立 protect） |
| HTTP 代理 VPN 模式（可选，无默认路由） | ✓ |
| 系统代理 | 不适用 |
| 流量：速率差分 + 曲线 + 内存 + 连接数 | ✓ |
| 出口 IP 检测（模式/端点/地理） | ✓ |
| 代理延迟测试（controller） | ✓ |
| 运行中切换路由模式（PATCH） | ✓ |
| 节点候选库 + 应用并重连 | ✓ |
| 配置摘要 / 文件导入 / 安全草稿 / 投影预览 | ✓（草稿与已应用配置分离，可仅保存或应用并重连） |
| 日志过滤（来源·级别·搜索）+ VPN 事件 | ✓ |
| 会话偏好持久化 | ✓ SharedPreferences（含候选/出口设置） |
| mihomo 资产拉取脚本 | ✓ `scripts/fetch-mihomo.mjs` |
| CloudflareSpeedTest 测速 | ✓（arm64；对齐 macOS：参数校验 / 参数面板 / IP 源 / 排序 / 首页测试节点 / 应用重连；`fetch-cfst.mjs`） |
| 快捷设置磁贴启停 | ✓（Clash/NekoBox 风格；共用 SessionStartGate） |
| Android 14+ 磁贴跳转兼容 | ✓（API 34+ 使用 `PendingIntent`，API 26–33 保留兼容路径） |
| 首页连接主控 + 通知实时速率/断开 | ✓（低打扰持续通知，可直接结束会话） |
| 配置剪贴板 YAML 导入 | ✓（不自动拉取订阅 URL） |
| 自适应导航壳 | ✓（底部栏 / 导航轨 / 上下文侧栏，按窗口宽度切换） |
| 品牌图标 | ✓（复用 macOS IPv6 标记；自适应 / 圆形 / Android 13 主题图标 + 磁贴 / 通知图标） |
| native hev/tun2socks | 可选增强（当前用户态转发已覆盖典型 TCP/UDP 应用流量） |

## 契约

修改投影前更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS `ContractFixtureTests`
- Windows `cargo test`
- Android `gradle :core:test`
