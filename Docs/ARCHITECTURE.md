# ViaSix 架构说明

本文描述 ViaSix 的模块边界、数据流、信任边界和进程生命周期。终端用户请从 [README](../README.md) 或[用户指南](USER_GUIDE.md)开始。

## 目录

- [总体结构](#总体结构)
- [启动与恢复](#启动与恢复)
- [可写数据](#可写数据)
- [节点测速流程](#节点测速流程)
- [代理配置流程](#代理配置流程)
- [系统代理生命周期](#系统代理生命周期)
- [网络接入边界](#网络接入边界)
- [运行组件安装](#运行组件安装)
- [进程与并发边界](#进程与并发边界)
- [信任边界](#信任边界)
- [分发模型](#分发模型)

## 总体结构

ViaSix 由 SwiftUI 应用、平台核心、Mihomo 配置模块、共享特权协议和 LaunchDaemon helper 组成：

```text
ViaSixApp（SwiftUI，@MainActor）
  App / Features / State / DesignSystem
                    │
          ┌─────────┴──────────┐
          ▼                    ▼
ViaSixCore               ViaSixMihomoConfig
  Persistence / Runtime    YAML / Profile / Migration
  Networking / Resources  Runtime composition
          │
          ├──────────────► Application Support
          │                用户数据与用户态子进程
          ▼
ViaSixPrivilegedProtocol ──► ViaSixTunHelper
固定 typed XPC methods       SMAppService LaunchDaemon
```

- `ViaSixApp`：窗口、菜单栏、用户交互和工作流编排。
- `AppModel`：主线程上的唯一应用状态协调者，持有并取消长任务。
- `ViaSixCore`：持久化、组件安装、测速、进程控制和 macOS 网络接入管理。
- `ViaSixMihomoConfig`：Mihomo YAML 解析、服务器表单、分享链接、Provider 约束、运行配置生成和旧 Xray JSON 迁移。
- `ViaSixPrivilegedProtocol`：app/helper 共用的协议版本、Mach service 常量、代码签名身份与固定 XPC 接口。
- `ViaSixTunHelper`：最小权限 LaunchDaemon；只运行固定签名 Mihomo，负责 TUN 会话、路由/DNS 生命周期、进程监督和崩溃恢复。
- `CfstRunner` / `MihomoController`：actor 隔离的自有进程生命周期。

UI 不直接启动进程或写运行配置；相关操作通过 `AppModel` 进入核心层。Mihomo 当前作为普通用户态 sidecar 运行。

## 启动与恢复

启动分为必需资源和可恢复状态两类：

1. 创建 Application Support、Mihomo home、Provider 与规则目录，并安装缺失的默认资源。
2. 检查上次会话遗留的系统代理快照，并在不覆盖外部修改的前提下尝试恢复 macOS 设置。
3. 加载用户偏好并规范化内置地址列表路径。
4. 加载固定清单中的运行组件状态。
5. 加载最近测速结果、`profile.yaml`、本机代理配置和可重新生成的 Mihomo 运行配置。
6. 检查 TUN LaunchDaemon 与 helper 状态；恢复同一用户的遗留 journal，或接管同一用户仍在运行的会话。其他用户的会话只作为占用状态展示，不提供停止、恢复、服务修复或运行时替换动作。

目录或默认资源无法准备属于致命启动错误。损坏的 `result.csv` 属于可丢弃缓存，不阻止启动；损坏的代理配置会记录警告并允许用户从“设置”重新导入或编辑。

旧版 `server.json` 优先于 `template.json` 作为一次性迁移输入。成功迁移后生成 `profile.yaml`；旧 JSON 保留在原路径，不会作为 Mihomo 运行配置执行。旧 `xrayPath` 偏好不会迁移为 `mihomoPath`。

## 可写数据

签名后的应用 bundle 始终按只读处理。可变数据位于：

```text
~/Library/Application Support/ViaSix/
  Data/
    preferences.json
    ip.txt
    ipv6.txt
    profile.yaml
    local-proxy.json
    system-proxy.json
    result.csv
    Mihomo/
      config.yaml
      controller.secret
      providers/
      rules/
  Runtime/
    cfst
    mihomo
  Logs/
```

目录权限为 `0700`，ViaSix 管理的偏好、列表和配置文件权限为 `0600`。

- `profile.yaml`：用户可编辑的 Mihomo 服务器配置，保存 `proxies`、`proxy-providers`、`proxy-groups`、`rules`、`rule-providers` 和 `sub-rules` 等服务器侧内容。
- `local-proxy.json`：本机监听、协议行为、代理模式和互斥的网络接入方式。
- `Mihomo/config.yaml`：由前两者及当前节点生成的运行配置，可重新创建，不是用户配置的唯一来源。
- `Mihomo/controller.secret`：首次启动时生成的随机 Controller 鉴权密钥，权限为 `0600`；特权投影只把它与 `127.0.0.1` Controller 一起带入 root-owned 会话配置，不接受外部覆盖。
- `Mihomo/providers/` 与 `Mihomo/rules/`：Mihomo 在私有 home 中使用的 Provider 数据。
- `system-proxy.json`：仅在系统代理会话期间保存恢复快照，恢复完成后删除。

`LocalProxyConfiguration` 的持久化字段为：

| 字段 | 类型 | 默认值 | 边界 |
| --- | --- | --- | --- |
| `listenAddress` | String | `127.0.0.1` | 仅允许 `127.0.0.0/8`、`::1` 或 `localhost` |
| `port` | Int | `11451` | 1–65535 |
| `controllerPort` | Int | `9090` | 1–65535，且不能与 mixed 端口相同 |
| `udpEnabled` | Bool | `true` | Mihomo 节点 UDP 开关 |
| `sniffingEnabled` | Bool | `true` | Mihomo 协议嗅探开关 |
| `bypassPrivateNetworks` | Bool | `true` | 规则模式中的私有网段直连规则 |
| `logLevel` | String | `warning` | `silent`、`error`、`warning`、`info`、`debug` |
| `routingMode` | String | `rule` | `rule`、`global`、`direct` |
| `networkAccessMode` | String | `localProxy` | `localProxy`、`systemProxy`、`virtualInterface`，三者互斥 |
| `tunStack` | String | `mixed` | `mixed`、`system`、`gvisor` |
| `tunMTU` | Int | `1500` | 1280–9000 |
| `tunStrictRoute` | Bool | `false` | Mihomo 严格路由开关 |

解码旧文件时，`systemProxyEnabled: true` 迁移为 `networkAccessMode: systemProxy`，旧日志级别 `none` 迁移为 `silent`。网络接入方式是单一值，避免系统代理与虚拟网卡同时被请求。

默认资源只在目标不存在时复制。升级时只有与历史默认内容 SHA-256 完全匹配的文件才会迁移，用户编辑过的资源必须保留。

## 节点测速流程

```text
SpeedTestParameters
  → 参数校验和 CLI 映射
  → CfstRunner 启动独立进程组
  → 合并并流式解析 stdout / stderr
  → 读取本次新生成的 result.csv
  → AppModel 更新结果与选择状态
```

- 启动前删除旧 `result.csv`，失败任务不能复用缓存成功结果。
- 取消时同时取消调用任务并结束整个自有进程组。
- 主进程退出后会清理同组残留子进程，再等待输出 EOF。
- CSV、控制台输出和取消错误映射由单元测试覆盖。

## 代理配置流程

```text
                         ┌─ rule/global ─ profile.yaml
local-proxy.json + 模式 ─┤                  + 可选当前节点
                         └─ direct ────── 不读取远端节点或 Provider
  → 生成 Data/Mihomo/config.yaml（原子写入，0600）
  → mihomo -t -d Data/Mihomo -f Data/Mihomo/config.yaml
  → 启动仅监听回环地址的 mixed 入站
  → 通过仅监听 127.0.0.1 的 Controller 读取代理组、Provider、连接、规则、流量和内存
  → 用户操作通过带 Bearer 鉴权的 Controller API 切换代理、测试延迟、更新 Provider 或关闭连接
```

三种路由模式的运行时语义为：

- `rule`：保留导入的规则和代理组；没有代理组时创建 ViaSix 管理的选择组。可选加入私有 IPv4/IPv6 网段直连规则，并在缺少最终规则时追加 `MATCH`。
- `global`：由 Mihomo 的 `mode: global` 处理进入本地端点的流量，要求有效的内联节点或 Proxy Provider。
- `direct`：生成 `MATCH,DIRECT`，且不把 `proxies`、Provider、代理组或远端规则写入运行配置；不要求服务器配置或当前节点。

`profile.yaml` 可以是单个 Mihomo 节点、多个内联节点，或使用 HTTP/inline Proxy Provider 的配置。ViaSix 会把 HTTP Provider 的缓存路径约束到私有 `providers/` 或 `rules/` 目录，拒绝任意本地文件 Provider 路径。

候选节点只会覆盖第一个具有 `server` 字段的内联代理地址，并保留端口、凭据、TLS/REALITY 标识和其余节点。没有选择候选节点时保留原服务器地址；Provider-only 配置无需选择候选节点，且不会改写订阅内容。

运行配置固定 `allow-lan: false` 并校验回环监听、端口、占位凭据和 YAML 结构。生成完成后先用 Mihomo 自身校验，再启动用户态进程并探测 mixed 端口；校验失败不会提交为运行状态。

Mihomo 的 Controller 固定绑定 `127.0.0.1`，端口来自 `controllerPort`，每个请求使用本机随机密钥进行 Bearer 鉴权。导入 YAML 时会剥离 `external-controller` 和 `secret`，避免远端配置扩大监听范围或替换密钥；用户态和特权/TUN 投影都会重新生成同一个回环 Controller，而不是信任导入字段。

运行时 Controller 层采用与 Clash Verge 相同方向的数据面分层，而不是让每个页面独立轮询：

1. Mihomo 进入运行态后执行一次完整 HTTP 快照，读取版本、代理组、连接、规则、累计流量和内存。
2. 随后建立带 Bearer 鉴权的 `/connections` WebSocket，持续接收高频连接、累计流量和内存状态。
3. 版本、代理组和规则通过独立的低频元数据任务每 10 秒刷新，不再每秒重复请求。
4. WebSocket 异常结束时保留最后成功状态，标记为“重连中”，等待 1 秒后建立新连接；初始 HTTP 快照失败时也可由 WebSocket 数据与元数据请求恢复。
5. Mihomo 停止、重启或应用退出时取消连接流、元数据任务和待执行操作，旧流在取消后不能写入新一代运行状态。

所有页面继续观察同一个 `AppState.MihomoRuntimeState`。流量曲线只保留最近 60 个采样；相邻连接快照中消失的连接进入仅驻留内存的关闭历史，最多保留 200 条，并在内核停止时随运行状态一起清空。代理组延迟测试、Provider 更新和连接关闭串行执行，避免用户操作与状态流相互覆盖。Provider URL 与缓存仍由配置校验层约束，Controller 只负责读取和请求内核更新。

## 系统代理生命周期

系统代理是独立于 Mihomo 路由模式的网络接入层，由 actor 隔离的 `SystemProxyManager` 通过 macOS SystemConfiguration API 管理，不执行 `networksetup` 等 shell 命令。

启用流程：

1. 仅在 Mihomo 本地 mixed 入站启动成功且 `networkAccessMode == systemProxy` 时继续。
2. 读取所有当前启用的 macOS 网络服务，并在任何服务不支持代理协议时于修改前整体失败。
3. 保存每个服务完整的原始代理属性列表、协议启用状态和 ViaSix 将应用的目标值到 `Data/system-proxy.json`。
4. 在持有 SystemConfiguration 偏好锁时检查前置状态，并以一次事务把 HTTP、HTTPS 和 SOCKS 指向当前本地端点。
5. 保留旁路列表、PAC URL 与未知键，但在会话期间禁用 PAC，避免与固定代理同时生效。

恢复流程：

- 用户切换接入方式、停止 Mihomo 或退出 ViaSix 时，比较当前设置与 ViaSix 曾应用的值；未被外部修改的服务恢复为完整原始属性列表。
- 其他应用或用户已经修改的服务不会被旧快照覆盖；不存在的服务只记录报告。
- Mihomo 意外退出会触发异步恢复；强制终止留下的快照会在下次应用启动时恢复。
- 应用系统代理失败时执行尽力回滚。正常停止时若恢复失败，优先保留仍可用的本地监听，避免系统应用指向已经关闭的端口。

保存 `networkAccessMode == systemProxy` 不代表 macOS 此刻已启用代理；只有 Mihomo 运行且系统配置事务成功时，UI 才报告系统代理已启用。

## 网络接入边界

路由模式决定“进入 Mihomo 之后如何出站”，网络接入方式决定“哪些应用会进入 Mihomo”。本地代理只接收显式配置端点的应用；系统代理只影响遵循 macOS 代理设置的应用。

TUN 是独立于本地代理和系统代理的第三种接入层。AppModel 只有在 LaunchDaemon 已批准、固定签名 Mihomo 已就绪且 helper feature set 完整时才允许选择和启动。helper 从 typed envelope 重新生成配置，以固定 `-d`/`-f` 参数启动 root-owned Mihomo，负责自动路由、严格路由、DNS hijack、IPv4/IPv6、回环防护、网络变化状态和 journal 恢复。会话按登录用户 UID 单一归属；非所有者只能观察脱敏状态，不能停止、恢复或通过重注册服务影响现有会话。应用重新激活时会刷新服务批准与 helper 状态。系统代理与 TUN 永不同时应用；运行期间切换必须先停止会话。完整安全边界见[虚拟网卡能力边界](VIRTUAL_NETWORK.md)。

## 运行组件安装

运行清单为每个 CPU 架构固定上游版本、资产 URL、压缩格式、压缩包 SHA-256、解压后文件大小和 SHA-256：

1. 用户按组件选择 CFST 或 Mihomo；从清单中的 GitHub HTTPS URL 下载到临时目录，不查询 `latest`。
2. 校验压缩包 SHA-256。
3. 使用受限 ZIP/GZIP 解压器提取预期 payload，拒绝路径穿越、符号链接和意外文件。
4. 校验解压后文件的大小、SHA-256 与可执行权限。
5. 在完整验证后事务性替换所选 payload，并保留另一个受管组件；失败时保留旧的可用 Runtime。

当前固定组件为 CloudflareSpeedTest v2.3.5 和 Mihomo v1.19.29，分别按 arm64/x86_64 选择资产。Mihomo 安装成功后会清理旧运行目录中的 `xray`、`geoip.dat` 和 `geosite.dat`。

自定义路径在每个组件条目中独立选择，优先于 ViaSix 管理副本，其后依次查找 Homebrew 常用目录和当前 `PATH`。自定义文件只记录路径，不复制进受管 Runtime；旧 `xrayPath` 永远不会作为 Mihomo 路径执行。

## 进程与并发边界

- UI 和 `AppModel` 保持在 `@MainActor`。
- CFST、Mihomo、系统代理、虚拟网卡能力探测、偏好和组件管理使用 actor 隔离。
- 每个会改变外部状态的长任务都由 `AppModel` 持有；退出时先取消，再停止自有进程并等待任务收敛。
- ViaSix 从不按进程名全局结束进程，只向自己创建并仍持有的 PID / 进程组发送信号。
- Mihomo 启动包含配置校验、端口占用检查、就绪探测、超时、异常退出和清理路径。

## 信任边界

| 输入或组件 | 信任方式 | 主要风险 |
| --- | --- | --- |
| 内置资源 | 随应用源码和签名发布 | 错误默认值、迁移覆盖 |
| 在线运行组件 | 固定版本 URL、压缩包与 payload 双重校验 | 上游供应链、许可证变化 |
| 自定义可执行文件 | 用户为单个组件明确选择路径 | 恶意或架构不兼容二进制 |
| Mihomo YAML | 大小/深度/复杂度、字段与 Provider 类型校验 | 凭据泄露、错误服务器配置、订阅副作用 |
| 旧 Xray JSON | 只读解析并转换受支持的单节点结构 | 迁移语义差异、敏感凭据 |
| macOS 网络代理设置 | SystemConfiguration 锁、前置状态比较和恢复快照 | 权限失败、外部并发修改、异常退出遗留 |
| 特权 helper | 正式包使用相同 Team ID；本地包使用 root-owned 策略中的 App/helper 精确 CDHash；再校验 UID/audit session 与固定 XPC methods | 非法客户端、协议混淆、特权接口过宽、恢复失败 |
| 虚拟网卡后端 | 固定签名 Mihomo、最小权限 helper、typed envelope、PID/会话 journal 和恢复校验 | 默认路由回环、DNS 泄漏、外部路由修改、残留进程 |
| 自定义 IP / CIDR / URL | 参数校验后交给 CFST | 过量网络负载、不可信目标 |
| 出口 IP 服务 | 用户可配置的 HTTP / HTTPS 响应并验证 IP 格式 | 可用性、第三方日志和错误数据 |

## 分发模型

正式分发面向 Developer ID 签名、公证和非 Mac App Store 安装。包含 LaunchDaemon 的 app 必须公证，并建议安装到 `/Applications`；helper 或 plist 更新后必须先异步 unregister，等待完成后再 register。本地 ad-hoc 构建走独立管理员安装路径：完整 App 固定复制到 root-only 系统目录，legacy LaunchDaemon 只从该副本启动 helper，策略以精确 CDHash 双向绑定当前 App 与 helper。普通本机代理仍可使用 Application Support 中由用户管理的 Mihomo，CFST 也以普通用户权限运行；helper 不能执行用户可写 Runtime 中的程序。供特权路径使用的固定 Mihomo 位于 app 的 `Contents/Library/HelperTools/`，并由签名后的 `PrivilegedRuntime.plist` 绑定完整摘要和 CDHash。

开发运行使用 SwiftPM 的 `Bundle.module` 读取资源。打包构建定义 `VIASIX_PACKAGED_APP`，只从 `Bundle.main` 读取资源并启用 dead stripping，避免把本机 SwiftPM 资源路径带入分发二进制。应用包验证会检查默认本机配置、许可证、App/helper/installer/Mihomo 嵌套签名、Mihomo 版本与架构、运行时清单摘要/CDHash 和本地路径泄漏，并拒绝重新打包旧 Xray 默认资源。
