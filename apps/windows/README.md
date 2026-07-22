# ViaSix for Windows

**状态：MVP 骨架（用户态投影 + Mihomo 启停）**

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

## 当前范围

| 能力 | 状态 |
| --- | --- |
| contracts 投影（rule/global/direct + 拒绝用例） | ✓ |
| UI：导入 YAML、选 IPv6、生成运行配置 | ✓ |
| 用户态 Mihomo 启停 | ✓（需 `prebuild`） |
| 系统代理（WinINET 注册表 + 快照恢复） | ✓（仅 Windows 构建） |
| 出口 IP 检测（ipify HTTPS） | ✓ |
| 测速（CFST） | ✓（`pnpm prebuild` 拉取） |
| Wintun / Service | 未做（二期） |
| NSIS CI 构建 | ✓（`.github/workflows/windows-build.yml`） |

## 契约

修改投影行为前请更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS：`ContractFixtureTests`
- Windows：`cargo test` in `src-tauri`
