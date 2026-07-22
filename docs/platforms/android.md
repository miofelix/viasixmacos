# Android 应用

实现位置：[`apps/android`](../../apps/android)。

**状态**：MVP 骨架（投影 + VpnService 会话）。

## 技术选型

| 项 | 选择 |
| --- | --- |
| UI | Kotlin + Jetpack Compose |
| 投影 | `:core` JVM 库，contracts 对齐 |
| 虚拟网卡 | `ViaSixVpnService`（`VpnService`） |
| 代理内核 | 预编译 mihomo（后续嵌入） |
| 系统代理 | 不支持 |

## 验证

```bash
make android-test
make android-skeleton
cd apps/android && gradle :core:test
```

配置与投影行为必须符合 [`contracts/`](../../contracts)。
