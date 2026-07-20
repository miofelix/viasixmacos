# 虚拟网卡能力边界

本文记录 ViaSix 在 macOS 上启用 Mihomo TUN 前必须满足的安全、权限和恢复条件。它是实现约束，不表示当前版本已经提供虚拟网卡服务。

## 当前状态

当前 Mihomo 以登录用户身份运行，只提供回环 mixed 端点。界面展示“本地代理”“系统代理”“虚拟网卡”三个互斥的网络接入方式，但“虚拟网卡”控制项不可启用；启动流程也会拒绝 `virtualInterface`。当前版本不会创建 `utun`、修改默认路由、劫持 DNS 或接管全部网络流量。

应用包包含 `SMAppService` LaunchDaemon helper、固定 XPC 探测协议和恢复协议骨架。helper 当前不启动 Mihomo、不读取用户配置，也不修改网络。因此“helper 已打包”不等于“TUN 已可用”。

## 数据面选择

ViaSix 不自研 IP 数据面。计划使用 Mihomo 内置的 sing-tun 能力处理：

- 创建和维护 `utun` 接口；
- TUN 栈与数据包转发；
- 自动路由与严格路由；
- 上游出口接口自动探测；
- DNS hijack 与 fake-ip 运行数据。

ViaSix 负责配置白名单、权限边界、进程监督、系统状态验证和精确恢复。不能把 Mihomo 配置中出现 `tun.enable: true` 当作系统已经安全进入 TUN 状态。

Network Extension / Packet Tunnel Provider 是长期可评估的另一条路线，但需要新的 target、entitlement、provisioning 和适合嵌入 Provider 的 Mihomo 库形态。当前可下载的 Mihomo 命令行文件不能直接作为 Network Extension 数据面。

## 特权与代码签名边界

- `~/Library/Application Support/ViaSix/Runtime/mihomo` 属于用户可写目录，root helper 永远不能执行它。
- 需要 root 启动时，Mihomo 必须作为固定版本的嵌套代码随 app 一起签名、公证，并安装到 root-owned、普通用户不可写的固定位置。
- 安装时必须验证外层 app、helper 和 Mihomo 的签名身份、Team Identifier、版本、架构和固定摘要；运行前再次验证目标不是符号链接且所有权/权限未变化。
- XPC 只接受固定的 typed 请求。禁止传入任意路径、argv、环境变量、shell 字符串或原始 YAML。
- helper 按调用者的代码签名 requirement、UID、audit session 和协议版本鉴权；不接受“只要来自本机即可”的宽泛判断。
- 特权进程使用固定参数直接 `posix_spawn`，不得经 `/bin/sh -c`，也不得复用允许任意命令的通用 supervisor。
- ad-hoc 构建没有可验证的 Developer ID Team 身份，只能运行用户态本地代理，不能注册或使用真实 TUN 服务。

## 配置边界

主应用可以从 `profile.yaml` 与 `local-proxy.json` 生成候选运行配置，但送入特权边界的只能是已验证、可复现的固定配置规格或受信任摘要。helper 不解析用户 YAML，也不替主应用决定代理规则。

允许的 TUN 参数必须有明确白名单和范围：

- stack：`mixed`、`system` 或 `gvisor`；
- MTU：576–9000；
- `auto-route`、`strict-route`、`auto-detect-interface`；
- 固定格式的 DNS hijack 目标；
- 经解析和规范化的路由排除地址；
- 可选 `utun` 名称只能匹配 `utun` 加数字。

服务器地址、Provider URL、规则内容和凭据仍属于用户态配置。特权协议不得返回这些敏感内容。

## 防回环与就绪验证

接管默认路由后，Mihomo 自己的上游连接若再次进入 TUN 会形成回环。启用前必须同时满足：

1. 当前物理默认出口已解析并记录接口、网关和地址族。
2. Mihomo 启用 `auto-detect-interface` 或经过验证的等效上游绑定。
3. 内联代理服务器和 Provider 端点已解析为可验证的绕行目标；地址变化时重新计算。
4. 应用新默认路由后，逐项确认上游目标不会重新命中 TUN。
5. 系统代理会话已经恢复，避免两个接入层同时捕获同一流量。

TUN 就绪不能只探测 mixed 端口，还必须确认：

- 预期 Mihomo PID/PGID 仍是 helper 启动的进程；
- 预期 `utun` 已创建，接口地址和 MTU 与会话一致；
- IPv4/IPv6 路由与排除规则完整；
- DNS hijack 行为与配置一致；
- 外部连通性和上游绕行均通过；
- 没有遗留的旧 ViaSix TUN 会话。

睡眠唤醒、网络服务切换、VPN 变化、默认网关变化和上游地址变化后，必须重新验证；不能继续沿用启动时结论。

## DNS 边界

Mihomo 的 `dns` 与 `dns-hijack` 负责接收被导入 TUN 的 DNS 查询，但 ViaSix 仍要验证 macOS 实际解析路径。不能仅凭配置存在就宣称“无 DNS 泄漏”。

若实现需要修改 macOS 网络服务的 DNS 设置，必须像系统代理一样保存完整原始状态、在同一偏好锁中比较前置值，并使用 CAS 语义恢复。外部已经修改的 DNS 不能被旧快照覆盖。

## 恢复 journal

每个 TUN 会话在改变系统网络前写入版本化 journal。至少记录：

- schema 和协议版本；
- 会话 ID、创建时间与配置摘要；
- Mihomo PID、PGID、进程启动时间和已验证的可执行摘要；
- `utun` 名称、接口地址、MTU 和状态；
- 原始默认路由、ViaSix 添加的路由和排除规则；
- 原始 DNS 状态与 ViaSix 应用的目标状态；
- 启动阶段和最近一次验证结果。

恢复必须确认目标仍属于该会话，再做精确清理。缺少 cleanup 实现、身份不匹配或 journal 无法验证时必须保留 journal 并报告失败，不能用空操作删除恢复记录。

停止顺序：

1. 阻止新的状态切换并停止接收新连接。
2. 使用 CAS 恢复 DNS 和路由，保留外部修改。
3. 停止并回收 helper 持有的 Mihomo 进程组。
4. 验证 `utun`、路由和 DNS 已离开 ViaSix 会话状态。
5. 仅在所有必需恢复完成后删除 journal。

helper 或 app 崩溃、强制退出、系统重启后，服务下次启动先审计 journal 并完成同一恢复流程。恢复失败时 fail closed，不得显示为已停止且已恢复。

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

启用普通用户可见的虚拟网卡控制项前，至少需要：

- 固定签名 Mihomo 的嵌套打包、安装、升级、回滚和卸载验证；
- helper 双向鉴权、重放/并发请求和协议降级测试；
- 配置白名单、摘要绑定和所有路径/参数拒绝测试；
- IPv4/IPv6、Wi-Fi/以太网、睡眠唤醒、网络切换和多 VPN 场景；
- Mihomo 启动失败、崩溃、强杀、helper 崩溃、app 强退和系统重启恢复；
- 路由/DNS 被用户或其他软件修改后的 CAS 恢复；
- Provider 更新与上游地址变化后的防回环验证；
- 隔离 Mac 或虚拟机上的真实 TUN、DNS 泄漏和卸载回归；
- GPL-3.0 源码与声明义务、嵌套代码签名、公证和安装说明审计。

在这些检查完成前，虚拟网卡模式保持不可用，文档和界面都不得声称 ViaSix 可以接管全部流量。
