# ViaSix for Android

**状态：MVP 骨架（contracts 投影 + VpnService 会话）**

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
gradle :core:test            # contracts fixtures
gradle :app:assembleDebug    # 生成 debug APK（需 Android SDK）
node scripts/fetch-mihomo.mjs  # 可选：下载 arm64 mihomo 到 assets（尚未接线）
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
| IPv6 优选 | 手动指定入口 IPv6（测速后续对齐） |
| 连接配置 | Profile YAML 编辑 + 运行配置投影预览 |
| 日志 | 会话活动时间线 |
| 设置 | 全量隧道开关、运行组件、关于 |

设计令牌与卡片组件见 `ui/theme/`（对应 macOS `VisualStyle` / `SurfaceCard` 等）。

## 当前范围

| 能力 | 状态 |
| --- | --- |
| contracts 投影 | ✓（`:core` 测试） |
| 分区导航 UI（对齐 macOS 信息架构） | ✓ |
| VpnService 权限与前台会话 | ✓ |
| mihomo 用户态启动（assets → filesDir） | ✓ |
| 全量隧道 IPv4 TCP→SOCKS + DNS protect | ✓（`Tun2SocksEngine`） |
| HTTP 代理 VPN 模式（可选，无默认路由） | ✓ |
| 系统代理 | 不适用 |
| 完整 UDP / 成熟 TCP 状态机 / IPv6 转发 | 简化实现，后续可换 hev/native |
| 会话偏好持久化 | ✓ SharedPreferences |
| Controller 健康 + 累计流量展示 | ✓ |
| mihomo 资产拉取脚本 | ✓ `scripts/fetch-mihomo.mjs` |
| CloudflareSpeedTest 测速 | 未实现（macOS 优先） |

## 契约

修改投影前更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS `ContractFixtureTests`
- Windows `cargo test`
- Android `gradle :core:test`
