# 跨平台推进路线

## 阶段 0 — 结构

- [x] Monorepo 目录与 contracts 骨架
- [x] `apps/macos` 承接现有实现
- [x] `apps/windows` / `apps/android` 占位骨架
- [x] CI：contracts job + macOS job
- [x] macOS 加载 `contracts/fixtures` 语义用例（`ContractFixtureTests`）

## 阶段 1 — Windows MVP

- [x] Tauri 2 工程骨架（`apps/windows`）
- [x] Rust 投影引擎 + contracts fixtures（`cargo test`）
- [x] 基础 UI：YAML 导入、IPv6、模式、运行配置预览
- [x] 用户态 Mihomo 启停（需 `pnpm prebuild`）
- [ ] 系统代理
- [ ] 测速 / 出口检测
- [ ] TUN / Windows Service（二期）
- [ ] 正式 NSIS 发布流水线（Windows runner）

## 阶段 2 — Android MVP

- Kotlin UI + VpnService
- 同一套 contracts / fixtures
- 无系统代理（隐藏 `systemProxyEnabled`）

## 阶段 3 — 共享实现（按需）

- 若多端投影漂移，再抽取 `packages/mihomo-config` 单实现
