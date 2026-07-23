# 跨平台推进路线

ViaSix 定位为 **全平台客户端**（macOS / Windows / Android / Linux）。各端共享 `contracts/` 行为，UI 与特权网络按平台实现。Linux 桌面尚未开工，路线上明确预留。

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
- [x] 虚拟网卡：Mihomo TUN + Wintun.dll（进程内；通常需管理员）
- [x] Mihomo controller 健康探测
- [x] 实时流量采样（`/connections` 轮询）
- [x] NSIS CI 流水线（`windows-build.yml`，Windows runner）
- [ ] 独立 Windows Service 隔离（可选增强）
- [ ] Authenticode 签名（需证书密钥，仓库外配置）

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
- [x] CFST IPv6 优选（解析/参数/拉取脚本/可取消运行/结果应用并重连；arm64）
- [x] CFST UX：结果排序、当前节点测速、设置页组件就绪检查
- [x] CFST 参数面板对齐 macOS（IPSourceMode + 模式/筛选/性能 + 持久化）
- [x] CFST 参数校验 + Overview「测试节点」配置测速入口
- [ ] 生产级 tun2socks（hev/native）与完整 UDP/IPv6

## 阶段 3 — 共享与发布

- [x] `packages/mihomo-config` 约定 + `validate-cases.mjs`
- [x] `packages/viasix-mihomo-config` Rust 投影库（Windows 使用）
- [x] Tag 触发 draft Release 工作流（`release.yml`）
- [ ] Swift/Kotlin FFI 统一到同一 Rust 库（可选，fixtures 已对齐）
- [ ] 各端签名产物挂到同一正式 Release（需签名密钥）

## 阶段 4 — Linux 桌面（规划中 / 未开发）

目标：**Linux 桌面 GUI**，技术栈与 Windows 对齐——**Tauri 2 + 共享 Rust 投影**，减少重复实现。

- [ ] 确定发行目标（优先：x86_64；可选 aarch64）与打包形态（AppImage / deb / flatpak 等，待定）
- [ ] 从 `apps/windows` 抽出桌面共用层，或新增 `apps/linux`（与 Windows 共享 `packages/viasix-mihomo-config` 与前端壳）
- [ ] 用户态 Mihomo 启停 + contracts 投影
- [ ] 系统代理（桌面环境相关：GNOME/KDE 等路径差异需抽象）
- [ ] 虚拟网卡：Mihomo TUN（权限模型与 capability / polkit 策略待定）
- [ ] 测速、流量、会话偏好与活动日志（对齐现有桌面五分区 IA）
- [ ] CI runner 与安装包流水线
- [ ] 平台文档：`docs/platforms/linux.md` 从规划更新为可用说明

> Linux **不在**「当前发布范围」内；阶段 1–3 的 Windows/Android 能力不因 Linux 未开工而视为未完成。详见 [COMPLETION.md](COMPLETION.md)。
