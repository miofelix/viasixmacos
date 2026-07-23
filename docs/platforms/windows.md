# Windows 应用

实现位置：[`apps/windows`](../../apps/windows)。

ViaSix **全平台**产品中的 Windows 端；桌面信息架构与 Linux 规划共用同一 Tauri 技术方向。

**状态**：主路径能力持续对齐 macOS（壳层 + 托盘 + 活动日志 + Profile 导入/摘要 + 可配本地端口）；TUN 仍为进程内 Wintun（非 macOS XPC helper 模型）。未来 [Linux 桌面](linux.md) 优先复用本栈。

## 技术选型

| 项 | 选择 |
| --- | --- |
| UI / 宿主 | **Tauri 2** + Vite/TypeScript（设计系统对齐 macOS `VisualStyle`） |
| 投影 | Rust `src-tauri/src/projection`（contracts 对齐） |
| 代理内核 | 预编译 mihomo（`pnpm prebuild`） |
| 系统代理 | WinINET 注册表（`ProxyEnable` / `ProxyServer`）+ 启动/退出恢复 |
| 活动日志 | 后端 `ActivityLog` + `activity-log` 事件 |
| 托盘 | Tauri tray-icon（关窗可隐藏到托盘） |
| 出口检测 | HTTPS ipify（`detect_exit_ip`） |
| 测速 | CFST（可取消、IPv6 预设、内置 `ipv6.txt` 列表、当前节点测试） |
| Profile | 数据目录 `profile.yaml` 保存/加载 + 文件导入 |
| 托盘 | 关窗进托盘；tooltip 实时上下行；菜单项随启停动态启用/文案 |
| 连通性 | 经本地 mixed 端口 HTTPS 探测出口 |
| 本机代理 | mixed 仅回环；端口 1–65535 且 mixed≠controller；rule/global 要求 IPv6（`local_proxy`） |
| 内核日志 | `runtime/mihomo.log`；`ingest_core_log` 并入活动流；日志页按钮 |
| Profile | 数据目录保存/加载 + 导入/导出文件 |
| 虚拟网卡 | Mihomo TUN + Wintun.dll（进程内；stack/MTU 可配；`tun_preflight` 启动前预检；**非** macOS XPC Service 隔离） |

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
