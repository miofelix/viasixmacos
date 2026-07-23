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

- 修复 Android TCP 忽略客户端 SYN 的 Window Scale 选项，协商缩放后仍把后续 16 位 advertised window 当作未缩放值，现代高速链路下行在途量被错误限制在 65,535 字节的问题；现解析并去重 kind 3、按 RFC 7323 将过大 shift 限制为 14，客户端提供选项时在 SYN-ACK 发布服务端 shift 0，后续窗口按客户端 shift 展开，同时以 131,070 字节重传缓存容量封顶实际在途数据，避免扩大窗口后撞满保留队列而误关会话。
- 修复 Android TCP 在验证客户端段序号是否落入接收窗口之前就处理 ACK，窗口外或完全陈旧的数据段仍可推进服务端确认并释放重传缓存，同时同步态还接受缺少 ACK 标志的 payload/FIN 的问题；现按 RFC 9293 使用统一的 65,535 字节窗口先验证零长度段或数据/FIN 首尾是否重叠，拒绝段只回当前 ACK 并停止全部状态推进，窗口与序号回绕测试覆盖 IPv4/IPv6 共用路径。
- 修复 Android TCP 对已存在会话收到任意序号的 RST 都立即关闭，陈旧或窗口外复位可错误终止健康连接的问题；同步态 RST 现仅在 socket 与序号状态完整发布后按 RFC 5961 校验客户端下一期望序号，精确命中才关闭，65,535 字节接收窗口内的非精确值触发既有每会话限速 challenge ACK，窗口外、回退序号或尚在建连的 RST 静默丢弃，序号回绕同样安全。
- 修复 Android TCP 已建立会话静默吞掉重复纯 SYN，而 SYN+ACK 仍可能落入发送窗口、payload 与 FIN 处理路径的问题；同步态现按 RFC 5961 对意外 SYN 回送每会话单调时钟限速的 challenge ACK，握手未完成时稳定重发原 SYN-ACK，并在两种情况下都立即停止该段的后续数据处理，避免异常控制位推进流状态或形成 ACK 放大。
- 修复 Android TCP 握手只校验 ACK 值，错误客户端序号、携带 SYN 的 ACK 也能提前放行下行 reader，且远端 socket 尚未建立时伪造 `ACK=0` 可能错误拒绝会话的问题；握手门现同时要求 socket 已发布、`SEQ=clientNextSeq`、`ACK=serverSeq`、ACK 标志存在且无 SYN/RST，并以 pending/completed/cancelled 原子三态保证取消后不可复活，同时仍允许第三次握手携带合法 payload/FIN。
- 修复 Android 用户态 TCP 在会话不存在或达到会话上限时静默丢弃 SYN、ACK 与数据段，应用只能等待自身超时的问题；CLOSED 状态现按 RFC 9293 生成无状态 RST，带 ACK 的输入使用 `SEQ=SEG.ACK`，其余输入确认包含 SYN/FIN 的完整段长度，同时保持 32 位序号回绕安全且绝不响应 RST。
- 修复 Android `Tun2SocksEngine.stop()` 只中断线程却不等待退出，且 SOCKS CONNECT、UDP ASSOCIATE、直连 DNS 等尚未发布的阻塞 socket 无法由会话表关闭，停止后可能继续存活到 5–10 秒网络超时的问题；建立中资源现进入并发安全的关闭注册表，停止会先关闭 TUN fd 与全部 in-flight I/O，再有界等待 reader、writer、维护线程和 worker pool 收敛，并禁止已停止实例被误重启。
- 修复 Android TCP 下行重传耗尽或服务端半关闭超时后只静默删除会话，客户端仍会等待到自身超时的问题；异常收敛现主动发送 `RST|ACK`，并使用客户端最新确认的服务端序号而非固定 `SEQ=0`，避免现代 TCP 栈因复位序号不在接收窗口而忽略通知。
- 修复 Android TUN reader 仍直接向非阻塞 SOCKS5 UDP `DatagramChannel` 写入，发送缓冲短暂不可写时会关闭整个 relay 并触发 ASSOCIATE 重连风暴的问题；UDP 发送现也进入同一 Selector reactor，每 relay 采用按数据报数和字节数双重有界队列，`OP_WRITE` 就绪后公平排空，队列饱和只丢当前数据报而不破坏关联。
- 修复 Android TCP 发送窗口等待和上行 writer 队列轮询使用 `System.currentTimeMillis()`，设备校时或墙上时钟跳变可能导致等待被意外延长或提前超时的问题；传输层有界等待现统一改用 `System.nanoTime()` 计算纳秒级剩余时间，与重传、半关闭和 UDP relay 生命周期一致。
- 修复 Android 把 SOCKS 远端正常 EOF 与下行读异常视为同一路径，并在发送服务端 FIN 前错误等待客户端上行队列最多 35 秒的问题；TCP 两个半关闭方向现彼此独立，正常 EOF 只等待本方向未确认数据后回送 FIN，读异常或内部下行失败则向客户端发送 RST 并立即释放会话。
- 修复 Android 用户态 TCP 握手忽略客户端 SYN 的 MSS 选项，且 SYN-ACK 不发布自身 MSS，较小路径 MTU 下仍可能生成对端无法接收的段、无 MSS 时也未采用协议默认值的问题；TCP 选项解析现安全遍历 EOL/NOP/变长选项并严格校验 MSS，ViaSix 在 SYN-ACK 中发布接口 MSS，下行按接口上限与客户端 MSS 的较小值切分，缺省使用 IPv4 536 / IPv6 1220。
- 修复 Android TCP 下行固定一次读取 16 KiB 并封装为单个 IPv4/IPv6 报文、可能远超用户配置的 VPN MTU 且 IPv4 仍设置 DF 的问题；转发引擎现接收会话实际 MTU，并分别扣除 20/40 字节 IP 头与 20 字节 TCP 头，把 SOCKS 下行切成不超过虚拟接口 MTU 的段。
- 修复 Android TUN 写线程在虚拟网卡 fd 写入失败后继续吞包且仍报告运行中，以及转发引擎在 `start()` 中途失败、尚未发布给 `VpnService` 时无法由外层回收部分资源的问题；TUN 读写任一方向退出现统一 fail-closed，启动异常会在原地关闭 reactor、线程池和已打开描述符后再向上抛出。
- 修复 Android 每条 SOCKS5 UDP ASSOCIATE 都永久占用一个通用 I/O worker、并发 UDP 端点可能挤占 TCP/DNS 转发容量的问题；UDP relay 现改用非阻塞 `DatagramChannel`，由单个 daemon `Selector` reactor 多路复用全部回包，单轮有界排空并每 5 秒探测控制 TCP，关停时统一回收已注册和待注册 relay。
- 修复 Android TCP 会话在代理连接完成后立即占用一个 I/O worker 等待客户端 ACK，并为每条连接永久保留独立上行 writer，导致 64 线程上限在半开或空闲连接下过早耗尽的问题；下行 reader 现仅在有效握手 ACK 后单飞启动，握手超时由共享维护线程回收，上行 writer 仅在队列/FIN 需要时启动并在空闲 1 秒后退出，退出竞态会检查待处理数据并安全重启。
- 修复 Android SOCKS5 UDP framing 接受非零 RSV、零目标端口和越界 `length`，且可在构造超过单个 UDP 数据报上限的 frame 后才由 socket 报错的问题；编码现前置校验端口与 65,535 字节总长，解码严格拒绝保留字段、分片、零端口、截断和调用方越界长度。
- 修复 Android 显式直连 DNS/UDP 使用未连接 socket、可能接受非目标来源数据报，忽略 `VpnService.protect` 失败，并用 4096 字节缓冲静默截断较大 EDNS 响应的问题；每查询 socket 现先保护再连接到指定上游，仅接受该地址/端口的回包，保护失败立即关闭，响应容量扩展到完整 UDP 数据报上限。
- 修复 Android SOCKS5 UDP ASSOCIATE 的控制 TCP 被代理重启/关闭后，本地 UDP socket 仍显示可写、活跃流量持续续期失效 relay 并永久黑洞的问题；UDP 接收超时现探测控制连接 EOF 并立即淘汰代际，UDP socket 同时连接到代理报告的 relay 地址以仅接收可信端点回包，且严格校验 ASSOCIATE 保留字、域名与可解析地址。
- 修复 Android TCP SOCKS5 CONNECT 只有连接超时、代理在 greeting/CONNECT 响应阶段停滞时可永久占住连接 worker，以及 EOF、写入或畸形响应异常未统一关闭 socket 的问题；握手现受独立 10 秒读超时约束，成功后恢复普通阻塞读取，所有失败路径可靠关闭资源并校验版本、保留字、地址类型与目标参数。
- 修复 Android TUN 使用无上限 cached worker pool、在 TCP 建连/双向转发、UDP relay 与直连 DNS 突发时可能持续创建线程的问题；阻塞任务现拆分为最多 16 个连接 worker 与 64 个 I/O worker，采用无隐式积压的即时拒绝策略，并在 TCP、UDP、DNS 各拒绝路径主动发送复位或释放会话、relay、permit。
- 修复 Android TUN 解析只检查 IPv4/IPv6 与 TCP/UDP 长度、不验证校验和的问题；现拒绝损坏的 IPv4 头、TCP、非零 IPv4 UDP 与 IPv6 UDP 报文，IPv4 UDP 允许 RFC 768 的零校验和，所有回包构造器生成有效传输层校验和并拒绝超出 16 位长度字段的地址族/负载组合。
- 修复 Android SOCKS5 UDP ASSOCIATE 建立与空闲回收/发送失败并发时，晚完成的 relay 可能脱离映射泄漏，或旧清理误关同端点新 relay 的问题；每个 relay 代际现以实例条件移除并原子发布/关闭，过期回调与重新注册串行化，控制 TCP 在连接前完成 VPN 保护，所有握手失败路径都会关闭已创建 socket。
- 修复 Android SOCKS5 UDP ASSOCIATE 仅在下一包 UDP 到来时顺便清理、无后续流量时空闲 socket 会保留到 VPN 停止的问题；共享维护线程现每 5 秒主动回收超过 60 秒未活动的 relay，过期判断使用单调时钟，并避免清理流程二次删除刚重新活跃的端点。
- 修复 Android TCP 下行丢包只能等待 RTO、连续重复 ACK 无法及时恢复的问题；当前三次有效纯重复 ACK 会触发一次有界快速重传，ACK 推进后重置计数，同一序列不会因 ACK 洪峰重复放大。
- 修复 Android TUN reader 直接向远端 TCP socket `write/flush`、在慢远端或内核背压时阻塞整个隧道读线程的问题；客户端上行 payload 现进入每会话 64 KiB 有界队列，由独立 writer 顺序排空，队列满时保留旧 ACK 促使客户端重传，FIN 等待排队数据真正写完后再执行 `shutdownOutput`。
- 修复 Android IPv4 分片在没有重组器时可能被误交给 TCP/UDP 解析的问题；现拒绝 `MF`、非零 fragment offset 与保留标志，避免首片残缺 payload 或非首片字节污染用户态流连接。
- 修复 Android 远端 FIN 发出后立即销毁 TCP 会话、导致 FIN 丢失无法重传及双方半关闭未完成的问题；FIN 现占用序列空间并纳入未确认段缓存，等待客户端 ACK，双方 FIN 完成后关闭，迟迟不完成的半关闭在 60 秒后回收，客户端 FIN 后的非法 payload 不再写入 SOCKS。
- 修复 Android IPv6 转发只识别固定 40 字节头、把常见扩展头后的 TCP/UDP 流量直接丢弃的问题；现有界遍历 Hop-by-Hop、Routing、Destination Options、AH 与原子 Fragment，按真实上层偏移解析，并拒绝截断、超过 8 层或需要 IP 重组的分片链。
- 修复 Android 显式直连 DNS/UDP 在查询突发或上游超时时可无界占用 cached worker 线程与 socket 文件描述符的问题；直连查询现设 32 个 in-flight 硬上限，超限在创建资源前丢弃，且正常、异常与任务拒绝路径均可靠归还幂等 permit。
- 修复 Android TCP 下行数据只发送一次、短连接远端 EOF 后立即释放会话导致丢包无法恢复的问题；未确认段现按会话有界保留，以共享定时器和指数退避重传，支持累计/部分 ACK 与序列号回绕，并在数据确认后再发送 FIN，重试耗尽时主动收敛会话。
- 修复 Android TCP 下行忽略客户端 advertised window、在零窗口或未确认数据占满窗口后仍继续读取远端 socket 的问题；ACK 现以回绕安全的已发送边界推进确认序列，拒绝确认未发送数据与倒退确认，并在发送队列可见前原子登记序列以避免快速 ACK 竞态。
- 修复 Android TUN 解析接受超出实际帧长度的 IPv4/IPv6、TCP 或 UDP 声明，可能触发缓冲区异常并让读线程静默死亡的问题；畸形帧现被丢弃，读线程退出必定更新监督状态。
- 修复 Android TCP 会话在发出 SYN-ACK 后未等待客户端 ACK 就提前完成握手，以及重复 SYN 无法恢复的问题；远端下行现等待有效 ACK，握手超时自动清理，并稳定重发同一 SYN-ACK。
- 修复 Android TUN 出站队列在 UDP 洪峰或慢设备写入时可能淘汰 TCP 数据段的问题；TCP SYN、数据、FIN 与 RST 现使用有界无损队列并向远端读取施加背压，可丢数据报只能替换其他可丢项。
- 修复 Android 用户态 TCP 转发把乱序段写入 SOCKS、32 位序列号回绕判断错误，以及远端 EOF 未向应用发送 FIN 导致连接悬挂的问题；客户端 FIN 现按半关闭语义处理。
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
