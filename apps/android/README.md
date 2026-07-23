# ViaSix for Android

ViaSix **全平台**产品中的 Android 端。跨端总览见根 [README](../../README.md)。

**状态：生产可用**（contracts 投影 + VpnService 全量隧道 TCP/UDP IPv4/IPv6 + 五分区 UI，对齐 macOS 语义；无系统代理 / 无菜单栏为平台差异）

## 模块

| 模块 | 说明 |
| --- | --- |
| `:core` | 纯 JVM：Mihomo 投影，对齐 monorepo contracts fixtures |
| `:app` | Compose UI + `ViaSixVpnService` + 用户态 `Tun2SocksEngine` |

## 要求

- JDK 17+
- Android SDK（组装 APK 时）
- Gradle（本机 `gradle` 或后续 wrapper）

## 命令

```bash
cd apps/android
gradle :core:test            # contracts + CFST 解析/参数
gradle :app:test             # app 单元测试（CFST、隧道 framing/NAT/包编解码等）
gradle :app:assembleDebug    # 生成 debug APK（需 Android SDK）
node scripts/fetch-mihomo.mjs  # 可选：下载 arm64 mihomo 到 assets
node scripts/fetch-cfst.mjs    # 可选：下载 arm64 CFST 到 assets（IPv6 优选）
```

仓库根：

```bash
make android-test
make android-skeleton
make android-assemble
```

## UI 结构（对齐 macOS）

自适应导航对应桌面端侧栏 `AppSection`：手机使用底部栏，横屏/折叠屏使用导航轨，平板和桌面窗口使用带连接上下文的侧栏。

| 分区 | 说明 |
| --- | --- |
| 首页 | IPv6 链路步骤、代理模式、网络接入、流量、IP / 应用信息 |
| IPv6 优选 | CFST 测速、结果表、应用 / 应用并重连 + 手动入口 |
| 连接配置 | Profile YAML 安全草稿、校验后应用/还原、运行中应用并重连 + 投影预览 |
| 日志 | 会话活动时间线 |
| 设置 | 全量隧道、IPv6 路由、VPN MTU/计费属性/局域网绕过、DNS、分应用路由、系统权限/后台运行、运行组件、关于 |

设计令牌与卡片组件见 `ui/theme/`（对应 macOS `VisualStyle` / `SurfaceCard` 等）。

## 当前范围

| 能力 | 状态 |
| --- | --- |
| contracts 投影 | ✓（`:core` 测试） |
| 分区导航 UI（对齐 macOS 信息架构） | ✓ |
| VpnService 权限与前台会话 / 重启重连 | ✓（设置页授权与系统“始终开启 VPN”入口；系统 VPN“配置”动作回流设置分区；Sticky/Always-on 恢复；启动中可安全取消；整栈就绪后才发布运行态；异常退出自动收敛） |
| mihomo 用户态启动（assets → filesDir） | ✓ |
| 全量隧道 IPv4/IPv6 TCP→SOCKS | ✓（ACK/SEQ/标志联合校验驱动握手，重复 SYN 稳定重发 SYN-ACK，同步态意外 SYN 与非精确窗口内 RST 使用每会话限速的 RFC 5961 challenge ACK，精确 RST 才关闭；CLOSED 状态与会话过载按 RFC 9293 无状态 RST；同步态普通段先按 RFC 9293 验证统一 65,535 字节接收窗口且必须携带 ACK；安全解析客户端 MSS 与 Window Scale，在 SYN-ACK 发布接口 MSS 和协商所需 shift 0，无 MSS 时使用协议默认值，对端缩放窗口展开后仍受 131,070 字节重传容量约束；SOCKS5 建连与握手均有 10 秒超时且失败关闭；有效 ACK 后才占用下行 worker，上行 writer 按 payload/FIN 单飞启动并空闲退出；下行按实际 VPN MTU 与客户端 MSS 较小值分段；两个半关闭方向独立，远端 EOF 仅等待本方向确认后发送可重传 FIN，读异常、重传耗尽与半关闭超时均以窗口内序号主动 RST；回绕安全序列；客户端接收窗口流控；双向有界队列与背压；所有传输层有界等待使用单调时钟；重复 ACK 快速重传；未确认段有界保留与退避重传；连接/I/O worker 分别硬限 16/64） |
| 全量隧道通用 UDP→SOCKS5 UDP ASSOCIATE | ✓（每本地源端口一条 ASSOCIATE；DNS 默认复用此路径；严格校验 RSV/FRAG/端口/frame 长度；单 Selector reactor 多路复用所有非阻塞 relay 收发，不占通用 I/O worker；发送按 relay 采用数据报数/字节数双重有界队列并以 `OP_WRITE` 背压，饱和只丢当前数据报；空闲 60 秒主动回收；控制 TCP 每 5 秒探测 EOF；UDP 回包源绑定；relay 代际原子发布与按实例关闭） |
| TUN 帧与生命周期安全 | ✓（IPv4/IPv6 与 TCP/UDP 声明长度严格受实际帧边界约束；验证 IPv4 头、TCP、IPv6 UDP 与非零 IPv4 UDP 校验和，允许 IPv4 UDP 零校验和；IPv4/IPv6 需重组分片拒绝，IPv6 常见扩展头有界遍历；畸形帧隔离；读写任一方向退出均 fail-closed，启动中途失败会原地回收部分资源；停止主动关闭建立中的 TCP/UDP socket 与 TUN fd，并有界等待所有执行线程收敛） |
| DNS 路由 | ✓（TCP/UDP 默认经 mihomo/SOCKS，支持显式 protect 直连与自定义数字 IPv4/IPv6 服务器；UDP 直连查询有 32 个 in-flight 硬上限，socket 绑定上游来源并保留完整 EDNS 数据报） |
| VPN MTU | ✓（默认 1500；可在 macOS 同款安全范围 1280–9000 内调整） |
| VPN 计费属性 | ✓（Android 10+；默认保持平台计费行为，可显式标记为不计费） |
| 局域网绕过 | ✓（Android 13+ 原生路由排除；私网、链路本地、组播与广播） |
| IPv6 应用流量 | ✓（经 VPN / 阻止 / 绕过 VPN；默认经 VPN 且路由失败即中止） |
| 底层网络切换 | ✓（监听非 VPN 默认网络，Wi-Fi/蜂窝/以太网切换时显式更新 `setUnderlyingNetworks`，忽略旧网络迟到回调） |
| 分应用路由 | ✓（所有应用 / 绕过所选 / 仅代理所选；可搜索启动器应用或手动添加包名，无广泛包可见权限） |
| HTTP 代理 VPN 模式（可选，无默认路由） | ✓ |
| 系统代理 | 不适用 |
| 流量：速率差分 + 曲线 + 内存 + 连接数 | ✓ |
| 出口 IP 检测（模式/端点/地理） | ✓（会话运行时显式经本地 mixed 代理；停止时直连；IPv4/IPv6 模式校验返回地址族） |
| 代理延迟测试（controller） | ✓ |
| 运行中切换路由模式（PATCH） | ✓ |
| 节点候选库 + 应用并重连 | ✓ |
| 配置摘要 / 文件导入 / 安全草稿 / 投影预览 | ✓（草稿与已应用配置分离，可仅保存或应用并重连） |
| 日志过滤（来源·级别·搜索）+ VPN 事件 | ✓ |
| 会话偏好与恢复 | ✓ SharedPreferences（含当前分区、候选/出口设置）；进程重建立即恢复 VPN 运行态与授权中的启动动作 |
| mihomo 资产拉取脚本 | ✓ `scripts/fetch-mihomo.mjs` |
| CloudflareSpeedTest 测速 | ✓（arm64；对齐 macOS：参数校验 / 参数面板 / IP 源 / 排序 / 首页测试节点 / 应用重连；`fetch-cfst.mjs`） |
| 快捷设置磁贴启停 | ✓（Clash/NekoBox 风格；共用 SessionStartGate） |
| Android 14+ 磁贴跳转兼容 | ✓（API 34+ 使用 `PendingIntent`，API 26–33 保留兼容路径） |
| 首页连接主控 + 通知实时速率/断开 | ✓（低打扰持续通知，可直接结束会话） |
| Android 13+ 通知授权 | ✓（首次连接按需请求；拒绝不阻塞 VPN，设置页可修复且不重复打扰） |
| 后台运行稳定性 | ✓（显示电池优化状态并直达系统设置，不申请直接豁免权限） |
| 运行组件诊断与修复 | ✓（区分缺失/损坏/错误架构/权限；mihomo 与 CFST 可独立原子修复，运行中互锁） |
| 本地数据备份保护 | ✓（禁用云备份与设备迁移；配置 YAML、候选节点、运行密钥/状态均不离开设备） |
| 配置剪贴板 YAML 导入 | ✓（不自动拉取订阅 URL） |
| 自适应导航壳 | ✓（底部栏 / 导航轨 / 上下文侧栏，按窗口宽度切换） |
| 品牌图标 | ✓（复用 macOS IPv6 标记；自适应 / 圆形 / Android 13 主题图标 + 磁贴 / 通知图标） |
| native hev/tun2socks | 可选增强（当前用户态转发已覆盖典型 TCP/UDP 应用流量） |

## 契约

修改投影前更新 `contracts/fixtures/mihomo-config/cases`，并保证：

- macOS `ContractFixtureTests`
- Windows `cargo test`
- Android `gradle :core:test`
