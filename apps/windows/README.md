# ViaSix for Windows

ViaSix **全平台**产品中的 Windows 端。未来 Linux 桌面规划复用本 Tauri 栈（见 [docs/platforms/linux.md](../../docs/platforms/linux.md)）。

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
| UI：侧栏导航 + 五分区 + 侧栏代理坞（对齐 macOS） | ✓ |
| UI：流量曲线/内存、就绪校验、测速参数/排序/重连确认 | ✓ |
| UI：Profile 文件导入 + 后端 YAML 摘要 | ✓ |
| IPv6 预设段 / 内置 ipv6.txt 列表源、可取消测速、当前节点测速 | ✓ |
| Profile 数据目录落盘（profile.yaml 保存/加载） | ✓ |
| 托盘实时上下行 tooltip | ✓ |
| 代理连通性探测（经 mixed 端口） | ✓ |
| 内核 mihomo 日志尾部 | ✓ |
| TUN stack/MTU、UDP/嗅探可配 | ✓ |
| 用户态 Mihomo 启停（投影预检 + 端口可配） | ✓（需 `prebuild`） |
| 系统代理（WinINET 注册表 + 启动/退出恢复） | ✓（仅 Windows 构建） |
| 后端活动日志流（`activity-log` 事件） | ✓ |
| 系统托盘（显示 / 启停提示 / 停止 / 退出；关窗进托盘） | ✓ |
| 出口 IP 检测（ipify HTTPS） | ✓ |
| 测速（CFST） | ✓（`pnpm prebuild` 拉取） |
| NSIS CI 构建 | ✓（`.github/workflows/windows-build.yml`） |
| 会话偏好持久化 | ✓（含端口 / 托盘 / 测速参数） |
| Controller 健康探测 | ✓ |
| 实时流量（`/connections` + `/memory`） | ✓ |
| 虚拟网卡 Mihomo TUN + Wintun | ✓（需 wintun.dll + 通常需管理员；见 Docs/VIRTUAL_NETWORK.md） |
| 独立 Windows Service 隔离 | 未做（可选增强） |

## 契约

修改投影行为前请更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS：`ContractFixtureTests`
- Windows：`cargo test` in `src-tauri`
