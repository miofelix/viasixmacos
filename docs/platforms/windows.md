# Windows 应用

实现位置：[`apps/windows`](../../apps/windows)。

**状态**：MVP（用户态投影 + Mihomo 启停）。

## 技术选型

| 项 | 选择 |
| --- | --- |
| UI / 宿主 | **Tauri 2** + Vite/TypeScript |
| 投影 | Rust `src-tauri/src/projection`（contracts 对齐） |
| 代理内核 | 预编译 mihomo（`pnpm prebuild`） |
| 系统代理 | WinINET 注册表（`ProxyEnable` / `ProxyServer`）+ 快照恢复 |
| 出口检测 | HTTPS ipify（`detect_exit_ip`） |
| 测速 | CFST v2.3.5（`pnpm prebuild` + `run_speed_test`） |
| 虚拟网卡 | Windows Service + Wintun（二期） |

## 验证

```bash
make windows-test      # contracts fixtures
make windows-skeleton
cd apps/windows && pnpm install && pnpm prebuild && pnpm app:dev
```

配置与投影行为必须符合 [`contracts/`](../../contracts)。
