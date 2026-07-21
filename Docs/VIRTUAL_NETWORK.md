# 虚拟网卡能力边界

本文记录 ViaSix 在 macOS 上启用 Mihomo TUN 时的安全、权限和恢复边界。它既是实现约束，也是发布包中“虚拟网卡服务”状态与故障恢复的说明。

## 当前状态

ViaSix 同时支持登录用户态本地代理/系统代理和特权 TUN。三种接入方式由 `NetworkAccessMode` 互斥协调；选择 TUN 前必须完成 LaunchDaemon 授权、固定签名运行时安装和 helper 能力检查。启动时 helper 等待新 `utun` 接口与回环 Controller 同时就绪，停止时撤销会话并等待接口消失。

应用包包含 `SMAppService` LaunchDaemon helper、固定 XPC 探测协议和 root-only 固定运行时目录。helper 不读取用户可写 Runtime，不接受可执行路径、argv、shell、环境变量或原始 YAML；它从 typed envelope 重新生成受约束的 Mihomo 配置。

## 数据面选择

ViaSix 不自研 IP 数据面，使用 Mihomo 内置的 sing-tun 能力处理：

- 创建和维护 `utun` 接口；
- TUN 栈与数据包转发；
- 自动路由与严格路由；
- 上游出口接口自动探测；
- DNS hijack 与 fake-ip 运行数据。

ViaSix 负责配置白名单、权限边界、进程监督、系统状态验证和精确恢复。不能把 Mihomo 配置中出现 `tun.enable: true` 当作系统已经安全进入 TUN 状态。

Network Extension / Packet Tunnel Provider 是长期可评估的另一条路线，但需要新的 target、entitlement、provisioning 和适合嵌入 Provider 的 Mihomo 库形态。当前可下载的 Mihomo 命令行文件不能直接作为 Network Extension 数据面。

## 特权与代码签名边界

- `~/Library/Application Support/ViaSix/Runtime/mihomo` 属于用户可写目录，root helper 永远不能执行它。
- 供 root 启动的 Mihomo 固定放在 app 的 `Contents/Library/HelperTools/com.felix.viasix.mihomo`，先作为独立嵌套代码签名，再由外层 app seal 保护；对应的 `Contents/Resources/PrivilegedRuntime.plist` 绑定版本、架构、相对路径、identifier、签名后 SHA-256 和 CDHash。安装后仍须位于 root-owned、普通用户不可写的固定位置。
- 安装时必须验证外层 app、helper 和 Mihomo 的签名身份、Team Identifier、版本、架构和固定摘要；运行前再次验证目标不是符号链接且所有权/权限未变化。
- XPC 只接受固定的 typed 请求。禁止传入任意路径、argv、环境变量、shell 字符串或原始 YAML。
- helper 按调用者的代码签名 requirement、UID、audit session 和协议版本鉴权；不接受“只要来自本机即可”的宽泛判断。
- TUN journal 绑定启动会话的 UID。普通 App 连接只能停止或恢复自己的会话；其他登录用户只能看到已占用/待恢复状态，拿不到会话 ID、路由模式或错误详情，也不能重新注册服务、替换特权运行时或接管会话。
- 特权进程使用固定参数直接 `posix_spawn`，不得经 `/bin/sh -c`，也不得复用允许任意命令的通用 supervisor。
- 有 Developer ID Team 身份时，App 与 helper 使用相同 Team ID requirement，并通过 `SMAppService` 注册。
- ad-hoc 构建没有可信 Team 身份，因此改用管理员安装器把完整 App 复制到 `/Library/Application Support/com.felix.viasix/InstalledApp/ViaSix.app`，由绝对路径 LaunchDaemon 启动 helper。root-only 策略绑定已安装 App/helper 的精确 CDHash 和获授权登录用户；日常 XPC 再校验固定 identifier、UID、audit session、协议版本和 feature set。普通 App 重编不替换特权服务，也不再次提权；helper 或协议不兼容时才要求修复。禁止从用户可写的 `dist/` 直接启动 root helper。

## 配置边界

主应用可以从 `profile.yaml` 与 `local-proxy.json` 生成候选运行配置，但送入特权边界的只能是已验证、可复现的固定配置规格或受信任摘要。helper 不解析用户 YAML，也不替主应用决定代理规则。

允许的 TUN 参数必须有明确白名单和范围：

- stack：`mixed`、`system` 或 `gvisor`；
- MTU：1280–9000；
- `auto-route`、`strict-route`、`auto-detect-interface`；
- 固定格式的 DNS hijack 目标；
- 经解析和规范化的路由排除地址；
- helper 只接受系统实际创建的 `utun` 加数字接口名，不接受用户指定设备名。

服务器地址、Provider URL、规则内容和凭据仍属于用户态配置。特权协议不得返回这些敏感内容。

## 防回环与就绪验证

接管默认路由后，Mihomo 自己的上游连接若再次进入 TUN 会形成回环。启用前必须同时满足：

1. 当前物理默认出口已解析并记录接口、网关和地址族。
2. Mihomo 启用 `auto-detect-interface` 或经过验证的等效上游绑定。
3. 内联代理服务器和 Provider 端点已解析为可验证的绕行目标；地址变化时重新计算。
4. 应用新默认路由后，逐项确认上游目标不会重新命中 TUN。
5. 系统代理会话已经恢复，避免两个接入层同时捕获同一流量。

TUN 就绪不能只探测进程存活，还必须确认：

- 预期 Mihomo PID/PGID 仍是 helper 启动的进程；
- 相比启动前基线出现预期的新 `utun` 接口；
- 回环 Controller 已监听且只绑定 `127.0.0.1`；
- IPv4/IPv6 路由与排除规则完整；
- DNS hijack 行为与配置一致；
- 外部连通性和上游绕行均通过；
- 没有遗留的旧 ViaSix TUN 会话。

睡眠唤醒、网络服务切换、VPN 变化、默认网关变化和上游地址变化后，必须重新验证；不能继续沿用启动时结论。

## DNS 边界

Mihomo 的 `dns` 与 `dns-hijack` 负责接收被导入 TUN 的 DNS 查询，但 ViaSix 仍要验证 macOS 实际解析路径。不能仅凭配置存在就宣称“无 DNS 泄漏”。

若实现需要修改 macOS 网络服务的 DNS 设置，必须像系统代理一样保存完整原始状态、在同一偏好锁中比较前置值，并使用 CAS 语义恢复。外部已经修改的 DNS 不能被旧快照覆盖。

## 恢复 journal

每个 TUN 会话在改变系统网络前写入版本化 journal。当前实现至少记录：

- schema 版本、会话 ID、所有者 UID、创建与更新时间；
- `preparing`、`running`、`restoring`、`failed` 等阶段和是否仍需清理；
- Mihomo PID、路由模式与本次创建的 `utun` 名称；
- 有界错误信息。

路由和 DNS 当前由 Mihomo TUN 进程直接拥有，因此恢复通过停止已核验身份的进程并等待对应 `utun` 消失完成。恢复 PID 时同时核对固定 root-owned 可执行路径和会话 Home 工作目录；身份不匹配、接口未消失或 journal 无法验证时保留记录并报告失败。若未来 helper 独立修改 macOS 路由或 DNS，则必须把原始值、应用值和 CAS 恢复证据加入 journal。

停止顺序：

1. 阻止新的状态切换并把 journal 标记为 `restoring`。
2. 停止 helper 持有的 Mihomo；恢复路径先核对 PID 的可执行文件与会话工作目录。
3. 等待本次 journal 记录的 `utun` 消失，由 Mihomo 撤销其自动路由与 DNS hijack。
4. 删除 root-only 会话配置目录。
5. 仅在所有必需清理完成后删除 journal。

helper 或 app 崩溃、强制退出、系统重启后，服务下次启动先审计 journal 并完成同一恢复流程。LaunchDaemon 启动阶段由 root 在接受客户端连接前处理跨进程崩溃恢复；服务运行期间，App 发起的恢复仍必须匹配 journal 所有者 UID。恢复失败时 fail closed，不得显示为已停止且已恢复。

服务注册、重新注册和特权 Mihomo 安装只允许在 journal 已确认 `inactive` 时执行。正式签名版本从“系统设置 → 登录项”回到前台后重新读取 `SMAppService` 与 helper 状态；本地构建通过 `launchctl` 读取固定 LaunchDaemon 状态。两条路径都不会为了刷新而修改路由或 DNS。

## 状态机

`NetworkAccessMode` 是本地代理、系统代理和虚拟网卡的唯一请求值。切换必须串行执行：

```text
当前方式停止并完成恢复
  → 验证系统处于基线状态
  → 准备目标方式
  → 提交目标运行状态
```

系统代理恢复失败时不能继续启用 TUN；TUN 恢复失败时也不能继续发布系统代理。应用退出必须等待当前切换收敛。

## 上线门槛

发布或升级普通用户可见的虚拟网卡控制项前，至少需要：

- 固定签名 Mihomo 的嵌套打包、安装、升级、回滚和卸载验证；
- helper 双向鉴权、重放/并发请求和协议降级测试；
- 配置白名单、摘要绑定和所有路径/参数拒绝测试；
- IPv4/IPv6、Wi-Fi/以太网、睡眠唤醒、网络切换和多 VPN 场景；
- Mihomo 启动失败、崩溃、强杀、helper 崩溃、app 强退和系统重启恢复；
- Mihomo 进程退出后的路由/DNS 清理；若未来 helper 独立修改系统网络设置，还必须覆盖外部并发修改下的 CAS 恢复；
- Provider 更新与上游地址变化后的防回环验证；
- 隔离 Mac 或虚拟机上的真实 TUN、DNS 泄漏和卸载回归；ad-hoc 构建还要覆盖首次授权、无密码日常复用、普通 App 重编兼容和 helper 升级后修复，但不把它当作可分发 TUN 发布包；
- GPL-3.0 源码与声明义务、嵌套代码签名、公证和安装说明审计。

以上条件缺一时，虚拟网卡保持禁用并显示具体修复动作；即使 TUN 已运行，应用也只承诺将符合 Mihomo 路由规则的 IPv4/IPv6 流量导入内核，不宣称绕过其他 VPN 或系统过滤器。
