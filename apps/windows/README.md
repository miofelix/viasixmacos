# ViaSix for Windows

**状态：UI 与 macOS 信息架构对齐（侧栏五分区 + 设计系统）**

技术栈：

- UI：Vite + TypeScript（Tauri WebView）
- 宿主：Tauri 2 + Rust
- 投影：`src-tauri/src/projection`（对齐 monorepo `contracts/fixtures`）
- 内核：预编译 mihomo（`pnpm prebuild` → `src-tauri/sidecar/`）

## 要求

- Node.js 20+ / pnpm
- Rust stable（MSVC toolchain on Windows）
- Windows 上还需 WebView2

macOS/Linux 上可运行 **投影契约测试** 与大部分开发流程；完整桌面壳建议在 Windows 验证。

## 命令

```bash
cd apps/windows
pnpm install
pnpm prebuild                 # 拉取当前 host 的 mihomo
cargo test --manifest-path src-tauri/Cargo.toml   # contracts fixtures
pnpm app:dev                  # Tauri 开发（需本机 GUI）
pnpm app:build                # 安装包（主要在 Windows）
```

从仓库根：

```bash
make windows-test             # cargo test（投影契约）
make windows-skeleton         # 目录/文件校验
```

## 界面结构（对齐 macOS）

| 分区 | 职责 |
| --- | --- |
| 首页 | IPv6 链路步骤、代理模式、系统代理/TUN、流量统计、IP 信息 |
| IPv6 优选 | CFST 测速、结果表、应用最佳节点 |
| 连接配置 | Profile YAML、投影预览、启停内核 |
| 日志 | 客户端会话日志（来源/级别筛选） |
| 设置 | Controller 健康、系统代理操作、Wintun/TUN、关于 |

前端模块：`src/main.ts`、`state.ts`、`views.ts`、`api.ts`、`styles.css`（设计 token 对齐 macOS `VisualStyle`）。

## 当前能力

| 能力 | 状态 |
| --- | --- |
| contracts 投影（rule/global/direct + 拒绝用例） | ✓ |
| UI：侧栏导航 + 五分区（对齐 macOS） | ✓ |
| UI：导入 YAML、选 IPv6、生成运行配置 | ✓ |
| 用户态 Mihomo 启停 | ✓（需 `prebuild`） |
| 系统代理（WinINET 注册表 + 快照恢复） | ✓（仅 Windows 构建） |
| 出口 IP 检测（ipify HTTPS） | ✓ |
| 测速（CFST） | ✓（`pnpm prebuild` 拉取） |
| NSIS CI 构建 | ✓（`.github/workflows/windows-build.yml`） |
| 会话偏好持久化 | ✓（app data `session-prefs.json`） |
| Controller 健康探测 | ✓ |
| 实时流量（controller `/connections` 轮询） | ✓ |
| 虚拟网卡 Mihomo TUN + Wintun | ✓（需 wintun.dll + 通常需管理员；见 Docs/VIRTUAL_NETWORK.md） |
| 独立 Windows Service 隔离 | 未做（可选增强） |

## 契约

修改投影行为前请更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS：`ContractFixtureTests`
- Windows：`cargo test` in `src-tauri`
