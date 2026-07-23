# ViaSix for Android

ViaSix **全平台**产品中的 Android 端。跨端总览见根 [README](../../README.md)。

**状态：MVP（contracts 投影 + VpnService 会话 + 分区 UI）**

## 模块

| 模块 | 说明 |
| --- | --- |
| `:core` | 纯 JVM：Mihomo 投影，对齐 monorepo contracts fixtures |
| `:app` | Compose UI + `ViaSixVpnService`（虚拟网卡语义骨架） |

## 要求

- JDK 17+
- Android SDK（组装 APK 时）
- Gradle（本机 `gradle` 或后续 wrapper）

## 命令

```bash
cd apps/android
gradle :core:test            # contracts + CFST 解析/参数
gradle :app:test             # app 单元测试（CFST runner 失败路径等）
gradle :app:assembleDebug    # 生成 debug APK（需 Android SDK）
node scripts/fetch-mihomo.mjs  # 可选：下载 arm64 mihomo 到 assets
node scripts/fetch-cfst.mjs    # 可选：下载 arm64 CFST 到 assets（IPv6 优选）
```

仓库根：

```bash
make android-test
make android-skeleton
```

## UI 结构（对齐 macOS）

底部导航对应桌面端侧栏 `AppSection`：

| 分区 | 说明 |
| --- | --- |
| 首页 | IPv6 链路步骤、代理模式、网络接入、流量、IP / 应用信息 |
| IPv6 优选 | CFST 测速、结果表、应用 / 应用并重连 + 手动入口 |
| 连接配置 | Profile YAML 编辑 + 运行配置投影预览 |
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
| 全量隧道 IPv4 TCP→SOCKS + DNS protect | ✓（`Tun2SocksEngine`） |
| HTTP 代理 VPN 模式（可选，无默认路由） | ✓ |
| 系统代理 | 不适用 |
| 流量：速率差分 + 曲线 + 内存 + 连接数 | ✓ |
| 出口 IP 检测（模式/端点/地理） | ✓ |
| 代理延迟测试（controller） | ✓ |
| 运行中切换路由模式（PATCH） | ✓ |
| 节点候选库 + 应用并重连 | ✓ |
| 配置摘要 / 文件导入 / 投影预览 | ✓ |
| 日志过滤（来源·级别·搜索）+ VPN 事件 | ✓ |
| 完整 UDP / 成熟 TCP 状态机 / IPv6 转发 | 用户态简化，后续可换 hev/native |
| 会话偏好持久化 | ✓ SharedPreferences（含候选/出口设置） |
| mihomo 资产拉取脚本 | ✓ `scripts/fetch-mihomo.mjs` |
| CloudflareSpeedTest 测速 | ✓（arm64；对齐 macOS：参数面板 / IP 源 / 排序 / 当前节点测速 / 应用重连；`fetch-cfst.mjs`） |

## 契约

修改投影前更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS `ContractFixtureTests`
- Windows `cargo test`
- Android `gradle :core:test`
