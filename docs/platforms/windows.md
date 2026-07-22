# Windows 应用

实现位置：[`apps/windows`](../../apps/windows)。

**状态**：功能 MVP 已齐；**UI 信息架构对齐 macOS**（侧栏：首页 · IPv6 优选 · 连接配置 · 日志 · 设置）。

## 技术选型

| 项 | 选择 |
| --- | --- |
| UI / 宿主 | **Tauri 2** + Vite/TypeScript（设计系统对齐 macOS `VisualStyle`） |
| 投影 | Rust `src-tauri/src/projection`（contracts 对齐） |
| 代理内核 | 预编译 mihomo（`pnpm prebuild`） |
| 系统代理 | WinINET 注册表（`ProxyEnable` / `ProxyServer`）+ 快照恢复 |
| 出口检测 | HTTPS ipify（`detect_exit_ip`） |
| 测速 | CFST v2.3.5（`pnpm prebuild` + `run_speed_test`） |
| 虚拟网卡 | Mihomo TUN + Wintun.dll（进程内；可选后续 Service 隔离） |

## UI 分区（与 macOS `AppSection` 对齐）

| 分区 | 内容 |
| --- | --- |
| 首页 | 链路就绪步骤、代理模式、系统代理/TUN、流量、入口/出口 IP |
| IPv6 优选 | CFST 测速与节点选择 |
| 连接配置 | Profile YAML 与运行配置投影 |
| 日志 | 客户端会话活动日志 |
| 设置 | Controller、系统代理、Wintun/TUN、关于 |

## 验证

```bash
make windows-test      # contracts fixtures
make windows-skeleton
cd apps/windows && pnpm install && pnpm prebuild && pnpm app:dev
```

## 打包 / CI

- 本地与 CI 说明：[apps/windows/Docs/RELEASING.md](../../apps/windows/Docs/RELEASING.md)
- Actions：`.github/workflows/windows-build.yml`（NSIS + exe artifact）

配置与投影行为必须符合 [`contracts/`](../../contracts)。
