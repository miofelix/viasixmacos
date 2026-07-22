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
- [x] 虚拟网卡 API 骨架（fail-closed；Wintun/Service 未实现）
- [x] Mihomo controller 健康探测
- [x] 实时流量采样（`/connections` 轮询）
- [ ] TUN / Windows Service 真实集成（需提权与签名决策）
- [x] NSIS CI 流水线（`windows-build.yml`，Windows runner）
- [ ] Authenticode 签名与正式 tag 发布

## 阶段 2 — Android MVP

- [x] Gradle 工程（`:app` + `:core`）
- [x] Kotlin 投影 + contracts fixtures（`gradle :core:test`）
- [x] Compose UI 生成运行配置
- [x] `VpnService` 权限/前台会话骨架
- [x] `assembleDebug` APK 可构建
- [x] mihomo 资产拉取脚本
- [x] 嵌入 mihomo 用户态 + VPN HTTP 代理（`setHttpProxy`）
- [x] 全量路由 + 用户态 IPv4 TCP/DNS 转发（`Tun2SocksEngine`）
- [x] 用户态 TCP 转发加固（会话上限 / 写队列 / 重传去重）
- [x] 无系统代理（产品矩阵已约定）
- [ ] 生产级 tun2socks（hev/native）与完整 UDP/IPv6

## 阶段 3 — 共享与发布

- [x] `packages/mihomo-config` 约定 + `validate-cases.mjs`
- [x] Tag 触发 draft Release 工作流（`release.yml`）
- [ ] 共享运行时（Rust/Go FFI）——仅当三端投影持续漂移时
- [ ] 各端签名产物挂到同一正式 Release
