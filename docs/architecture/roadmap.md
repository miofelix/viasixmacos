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
- [x] 系统代理（Windows 注册表 + 快照恢复；非 Windows stub）
- [x] 出口 IP 检测
- [x] 测速（CFST 拉取 + 运行 + 结果表）
- [ ] TUN / Windows Service（二期）
- [ ] 正式 NSIS 发布流水线（Windows runner）

## 阶段 2 — Android MVP

- [x] Gradle 工程（`:app` + `:core`）
- [x] Kotlin 投影 + contracts fixtures（`gradle :core:test`）
- [x] Compose UI 生成运行配置
- [x] `VpnService` 权限/前台会话骨架
- [x] `assembleDebug` APK 可构建
- [x] mihomo 资产拉取脚本（未接线）
- [ ] 嵌入 mihomo 与封包转发
- [ ] 无系统代理（产品矩阵已约定）

## 阶段 3 — 共享实现（按需）

- 若多端投影漂移，再抽取 `packages/mihomo-config` 单实现
