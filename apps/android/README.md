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

## 当前范围

| 能力 | 状态 |
| --- | --- |
| contracts 投影 | ✓（`:core` 测试） |
| 基础 UI 生成运行配置 | ✓ |
| VpnService 权限与前台会话 | ✓ 骨架（未嵌入 mihomo） |
| 系统代理 | 不适用 |
| 完整 TUN 封包转发 | 未做 |
| mihomo 资产拉取脚本 | ✓（`scripts/fetch-mihomo.mjs`，未接线） |

## 契约

修改投影前更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS `ContractFixtureTests`
- Windows `cargo test`
- Android `gradle :core:test`
