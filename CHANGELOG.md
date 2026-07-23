# 变更日志

本项目的重要变化记录在此。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)的意图；正式发布前仍需由维护者确认版本策略。

## [未发布]

### 变更

- 文档：明确 ViaSix 为 **全平台** 产品（macOS / Windows / Android / Linux），而非仅 macOS；根 README 以平台状态矩阵为入口。
- 文档：路线图增加 **阶段 4 — Linux 桌面**（Tauri，复用 Windows 栈；当前未开发），并新增 `docs/platforms/linux.md`。
- 文档：同步更新 `PRIVACY` / `SECURITY` / `CONTRIBUTING`、架构完成边界与各平台说明中的定位表述。
- 文档：Android 从 MVP 标记为 **生产可用**（五分区对齐 macOS；全量隧道 TCP/UDP IPv4/IPv6）；native hev 列为可选增强。
- Android：全量隧道由「仅 IPv4 TCP + DNS/53」升级为 SOCKS5 CONNECT（TCP）+ UDP ASSOCIATE（通用 UDP，含 QUIC）及 IPv6 转发。
- Android：参考 Clash Meta / NekoBox 增加快捷设置磁贴、首页连接主控、配置剪贴板导入、通知栏实时上下行速率（语义仍以 macOS 为准）。
- Android：导航壳适配手机、横屏/折叠屏和平板窗口，按宽度在底部栏、导航轨与 macOS 风格上下文侧栏间切换。
- Android：以 macOS IPv6 地址标记补齐自适应启动图标、圆形图标、Android 13 主题图标，以及专用磁贴/通知图标。
- Android：连接配置改为安全草稿工作流，导入/编辑不再立即覆盖可用配置；支持校验后应用、还原、仅保存及运行中应用并重连。
- Android：前台 VPN 通知增加一键断开动作，并采用低打扰、仅首次提醒的持续会话通知行为。
- Android：补齐 Android 13+ 会话通知运行时授权；首次连接按需询问，拒绝后继续 VPN 且不反复弹窗，设置页可再次授权或打开系统通知设置。
- Android：补齐会话恢复与单实例回流；旋转/进程重建后立即恢复当前分区和 VPN 运行态，系统授权中的启动动作不丢失，磁贴与通知可复用现有 Activity。
- Android：运行组件管理对齐 macOS 的缺失/损坏区分；校验 AArch64 ELF 格式、架构与执行权限，并支持 mihomo、CFST 独立原子修复/重装及运行中互锁。
- Android：补齐 Android 12+ 数据提取与旧版 Auto Backup 排除规则；继续禁用云备份和设备迁移，避免配置 YAML、候选节点、控制器密钥及运行状态离开设备。
- Android：强化 VPN 会话监督与系统恢复；运行状态绑定进程，Sticky 重启复用已保存配置，并在 mihomo/TUN 异常退出或 VPN 权限被撤销时自动收敛。
- Android：设置页增加 VPN 授权状态、独立授权操作和系统 VPN 设置入口，便于配置“始终开启 VPN”，从系统设置返回后会自动刷新。
- Android：设置页增加电池优化状态与系统入口，为长期连接和 Always-on VPN 提供后台稳定性指引，且不申请直接豁免权限。
- Android：增加 Clash/NekoBox 风格分应用路由，支持所有应用、绕过所选和仅代理所选三种模式，可搜索启动器应用或手动添加后台型应用包名；无需广泛包可见权限。
- Android：全量隧道 DNS 默认改为经 mihomo/SOCKS 转发，避免固定 UDP/53 直连；设置页支持显式直连模式及自定义数字 IPv4/IPv6 DNS 服务器。
- Android：增加可配置 VPN MTU，采用与 macOS 一致的 1280–9000 安全范围，贯通普通启动、快捷磁贴与 Sticky/Always-on 恢复。
- Android：增加 Android 10+ VPN 计费属性控制；默认保持平台行为，也可标记为不计费以减少系统对后台数据的限制。
- Android：增加 Android 13+ 原生局域网绕过，按需排除 IPv4/IPv6 私网、链路本地、组播与广播目标，默认仍保持全量 VPN 路由。
- Android：增加 IPv6 应用流量三态控制；默认经 VPN 且 IPv6 路由失败即中止，另提供阻止与显式绕过模式，避免静默 IPv6 旁路。
- Android：DNS 直连模式补齐 TCP/53 回退；TCP 套接字在连接用户指定 DNS 前先由 `VpnService.protect` 排除，现与 UDP/53 语义一致。
- Android：监听非 VPN 默认网络并通过 `setUnderlyingNetworks` 显式绑定 Wi-Fi、蜂窝或以太网；切换期间忽略旧网络迟到回调，并在首页、设置与会话日志展示当前状态。
- Android：向系统 VPN 面板注册配置入口；从 Always-on/VPN 设置触发“配置”时，无论冷启动或已有 Activity 都直接回到 ViaSix 设置分区。

### 新增

- Monorepo 布局：`contracts/`、`apps/macos|windows|android`、`server/`、`docs/architecture`；跨端契约与平台骨架就位。
- 跨端投影契约用例（`contracts/fixtures/mihomo-config/cases`）及 macOS `ContractFixtureTests` 对齐校验。
- Windows MVP：`apps/windows` Tauri 2 壳、Rust 投影引擎（contracts 对齐）、用户态 Mihomo 启停与基础 UI。
- Windows：系统代理启停（注册表快照恢复）与出口 IP 检测。
- Windows：CloudflareSpeedTest（CFST）拉取、测速运行与结果表。
- Android MVP：Gradle `:core` 投影（contracts 对齐）、Compose UI、`VpnService` 骨架。
- 跨端 `make projection-test`：macOS + Windows + Android 契约用例一键校验；Android mihomo 资产拉取脚本占位。
- Android：从 assets 安装 mihomo、VpnService 内启停内核，并通过 `setHttpProxy` 发布 mixed 端口。
- Android：全量隧道用户态转发（IPv4 TCP→mihomo SOCKS，DNS `protect` 出站），可切换仅 HTTP 代理模式。
- Windows：NSIS CI 流水线、sidecar 资源打包路径修复、发布说明 `apps/windows/Docs/RELEASING.md`。
- 共享：`packages/mihomo-config` 契约校验脚本；`make contracts-check` 集成；tag draft Release 工作流。
- Android：全量隧道转发加固（会话上限、写出队列、TCP 重传去重）。
- Windows：会话偏好持久化（profile / IPv6 / 模式 / 系统代理 / 测速参数）与版本号展示。
- Windows：版本对齐检查脚本（package.json / Cargo.toml / tauri.conf）。
- Android：会话偏好持久化（profile / IPv6 / 模式 / 全量隧道开关）。
- Windows：启动时写入 external-controller、提供 Controller 健康探测；虚拟网卡 API 失败关闭骨架与规划文档。
- Windows：首页实时流量（上下行速率与会话累计，轮询 controller `/connections`）。
- Android：启动后探测 controller 健康，并在 UI 轮询会话累计流量。
- Windows：Mihomo TUN + Wintun 虚拟网卡路径（`fetch-wintun`、启用后重启内核）；共享 crate `packages/viasix-mihomo-config`。
- 首页新增实时流量统计：上下行速率、近 10 分钟流量曲线、会话累计上传/下载与 Mihomo 内存占用。
- 连接运行中菜单栏显示两行上下行速率；菜单内同步展示速率摘要。
- 通过 Mihomo external-controller 的 `/traffic`、`/memory` 与 `/connections`（仅 totals）WebSocket 订阅采集数据，断线自动重连。
- 首页将 IPv6 入口与公网出口合并为「IP 信息」卡片，并新增「应用信息」卡片（版本、系统、运行方式、GitHub 链接）。

### 变更

- 首页调整卡片顺序：代理模式与网络设置移至流量统计上方。

### 修复

- 修复 Android 全量隧道使用平台默认非阻塞 TUN fd 时，`FileChannel.read` 可能因 `EAGAIN` 退出转发线程的问题；全量隧道现显式使用阻塞描述符。
- 修复 Android 在 VPN 启动中取消时，后台线程仍可能在停止清理后创建 mihomo、VPN 接口或流量监督线程的问题；启动现按资源阶段检查取消，并仅在整条栈就绪后发布运行态。
- 修复 Android 运行中的出口 IP 检测因 ViaSix 自身 UID 绕过 VPN 而误报物理出口的问题；主查询与地理补全现显式通过本地 mixed HTTP 代理，并校验 IPv4/IPv6 结果地址族。
- 修复 Android 在 VPN 运行或切换阶段仍可重置会话偏好、导致当前连接与后续 Sticky/Always-on 恢复配置分叉的问题。
- 修复 Android Always-on VPN 通过无 ViaSix 参数的系统 Intent 启动时误用空配置的问题；系统启动现恢复最后保存的有效会话参数。
- 修复 Android 日志时钟在应用运行期间切换系统区域设置后仍沿用旧 Locale 的问题。
- 修复 Android 14+ 快捷设置磁贴从折叠面板打开应用的兼容路径，并避免 API 26–28 访问 API 29 字幕接口；应用主题现覆盖 `minSdk 26`。
- 修复当前节点不可达时被误报为 CFST 未生成内部 CSV 文件的问题，并记录单节点测速的具体诊断信息。
- 修复本地代理启动过程中取消时可能留下僵尸进程、导致无法再次启动的问题。
- 修复退出失败后流量统计不会恢复、代理仍运行时界面停在“连接中”的问题。
- 修复流量监控 stop/start 竞态：节点切换或重启后可能永久丢失实时流量。
- 修复可执行文件就绪检测接受符号链接、但启动时被拒绝的不一致问题。
- 修复 TUN 会话恢复成功后未重新进入运行状态与流量监控的问题。
- 首页启动中可取消连接，与菜单栏行为一致。
- 当前节点结果匹配支持等价 IPv6 写法（压缩/展开）。

## [1.0.0] - 2026-07-22

### 新增

- 原生 macOS Mihomo 客户端，提供 Clash 风格的首页、代理、连接、规则、日志和设置界面。
- 支持规则、全局和直连模式，以及 Mihomo YAML、分享链接、内联节点和 Provider 配置。
- 支持代理组切换、批量延迟测试、活动连接管理、实时流量和内核规则查看。
- 集成 IPv4 / IPv6 节点测速，可筛选候选节点、复测当前节点并把结果应用到配置。
- 支持 HTTP / SOCKS 本机代理、macOS 系统代理生命周期管理和可选 TUN 虚拟网卡模式。
- 提供受签名与完整性约束的特权 TUN 服务、固定 Mihomo 运行时及安装修复流程。
- 提供运行组件下载、导入、校验、更新与取消操作，并固定审计第三方组件版本和摘要。
- 提供出口 IP 地址族选择、地理位置与网络信息，以及菜单栏快捷控制。
- 提供本地数据保护、配置事务恢复、进程监督、隐私说明和应用内帮助文档。
- macOS CI 覆盖格式、构建、测试和 arm64 应用打包验证。

### 变更

- 代理运行时从 Xray 迁移到 Mihomo，并补全原生配置模型和 Controller 集成。
- 统一 Clash 风格的信息架构、交互状态、组件管理和菜单栏操作。
- 将节点选择任务纳入应用生命周期，避免退出期间重新启动代理。
- 启动本地代理前提前检查连接模板，并在配置操作或节点切换期间统一收敛可用操作。
- 设置页直接显示代理配置导入/保存错误，避免只在主窗口通知中反馈。
- 节点页无结果时使用紧凑空状态，不再创建无意义的占位表格滚动区域。
- 损坏的历史测速结果或代理模板不再阻止应用进入可修复状态。
- 收紧应用数据目录和敏感配置文件的 POSIX 权限。
- 运行组件安装默认解析 GitHub 最新正式版本，并在替换前校验文件、架构和 SHA-256 完整性。
- 配置模板与当前配置使用可恢复事务发布，应用重启时会自动恢复中断的更新。
- 出口 IP 检测在自动、IPv4 和 IPv6 模式下统一补充位置、邮编、ISP、ASN 与时区信息。
- 打包构建不再嵌入本机项目检出路径。
- 连接页新增“测试当前节点”，保留协议与传输参数并自动隔离批量筛选条件。
- 设置页将代理配置编辑改为带实时校验、格式化、摘要和安全重载的应用内编辑器。
- 第三方许可改为应用内语义化目录和章节查看，文件系统操作降级为辅助菜单。
- 菜单栏按“打开 → 状态 → 代理 → 测速 → 复制 → 设置 → 退出”重排，展开/收起控件统一为整行 44pt 点击目标。
- 本地 ad-hoc 构建可安装并复用受精确 CDHash 约束的 TUN 特权服务，正式构建继续要求统一 Team ID。

### 修复

- 修复测速刚启动即停止时可能丢失取消的问题。
- 修复 CFST 主进程退出后残留子进程可能阻塞输出或成为孤儿的问题。
- 修复 Xray 启动时端口竞争被误判为已就绪的问题，并在冲突时给出明确提示。
- 修复应用异常退出后 CFST/Xray 监听端口可能继续占用的问题；每次运行现在由自有进程组和生命周期管道监管。
- 修复运行组件损坏、架构不匹配或截断的 universal Mach-O 文件被误认为可用的问题。
- 修复测速参数、配置未就绪和节点操作在应用启动阶段提前执行导致的误报与残留任务。
- 修复当前节点测速完成或取消时旧结果、空单位和异步回写状态不一致的问题。
- 修复长文档横向滚动条遮挡内容，以及无效文档链接静默失败的问题。
- 修复应用包内用户指南指向第三方声明的相对链接。
- 移除当前工作树中可还原旧代理连接资料的测试夹具。
- 修复特权 TUN 的恢复日志、运行时安装、helper 协议、会话复用和本地构建授权流程。
