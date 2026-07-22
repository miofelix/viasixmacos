# 跨平台推进路线

## 阶段 0 — 结构

- [x] Monorepo 目录与 contracts 骨架
- [x] `apps/macos` 承接现有实现
- [x] `apps/windows` / `apps/android` 占位骨架
- [x] CI：contracts job + macOS job
- [x] macOS 加载 `contracts/fixtures` 语义用例（`ContractFixtureTests`）

## 阶段 1 — Windows MVP

- 导入 profile，按 contracts 投影
- 用户态 mihomo、测速、基础 UI
- 系统代理（可选）
- TUN / Windows Service 留待二期

## 阶段 2 — Android MVP

- Kotlin UI + VpnService
- 同一套 contracts / fixtures
- 无系统代理（隐藏 `systemProxyEnabled`）

## 阶段 3 — 共享实现（按需）

- 若多端投影漂移，再抽取 `packages/mihomo-config` 单实现
