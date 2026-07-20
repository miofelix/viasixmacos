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

ViaSix 由 SwiftUI 可执行目标和不依赖 SwiftUI 的核心库组成：

```text
ViaSixApp（SwiftUI，@MainActor）
  App / Features / State / DesignSystem
                    │
                    ▼
ViaSixCore
  Models / Parsing / Configuration / Networking
  Infrastructure / Runtime / Resources
                    │
                    ▼
Application Support + ViaSix 自有子进程 + 第三方网络服务
```

- `ViaSixApp`：窗口、菜单栏、用户交互和工作流编排。
- `AppModel`：主线程上的唯一应用状态协调者，持有并取消长任务。
- `ViaSixCore`：配置校验、持久化、解析、组件安装和进程控制。
- `CfstRunner` / `XrayController`：actor 隔离的自有进程生命周期。

UI 不直接启动进程或修改运行配置；相关操作通过 `AppModel` 进入核心层。

## 启动与恢复

启动分为必需资源和可恢复状态两类：

1. 创建 Application Support 目录并安装缺失的默认资源。
2. 检查上次会话遗留的系统代理快照，并在不覆盖外部修改的前提下尝试恢复 macOS 设置。
3. 加载用户偏好并规范化内置地址列表路径。
4. 加载运行组件状态。
5. 尝试加载最近测速结果、拆分代理配置和派生 Xray 配置。
6. 进入可用界面。

目录或默认资源无法准备属于致命启动错误。损坏的 `result.csv` 属于可丢弃缓存，不阻止启动；损坏的代理模板或派生配置会记录警告并允许用户从“设置”重新导入或编辑。

## 可写数据

签名后的应用 bundle 始终按只读处理。可变数据位于：

```text
~/Library/Application Support/ViaSix/
  Data/
    preferences.json
    ip.txt
    ipv6.txt
    server.json
    local-proxy.json
    template.json
    config.json
    system-proxy.json
    result.csv
  Runtime/
    cfst
    xray
    geoip.dat
    geosite.dat
  Logs/
```

目录权限为 `0700`，ViaSix 管理的偏好、列表和配置文件权限为 `0600`。`server.json` 保存远端 `proxy` 出站；`local-proxy.json` 保存本机监听、协议行为、`routingMode` 和 `systemProxyEnabled`。`template.json` 是完整配置的兼容镜像，并保留完整 JSON 导入中的兼容字段；`config.json` 是按当前模式生成、可以重新创建的派生文件。`system-proxy.json` 仅在系统代理会话期间保存恢复快照，恢复完成后删除。

`LocalProxyConfiguration` 的持久化字段为：

| 字段 | 类型 | 默认值 | 边界 |
| --- | --- | --- | --- |
| `listenAddress` | String | `127.0.0.1` | 仅允许 `127.0.0.0/8`、`::1` 或 `localhost` |
| `port` | Int | `11451` | 1–65535 |
| `udpEnabled` | Bool | `true` | mixed 入站 UDP 开关 |
| `sniffingEnabled` | Bool | `true` | Xray 入站嗅探开关 |
| `bypassPrivateNetworks` | Bool | `true` | 规则模式的 `geoip:private → direct` 规则 |
| `logLevel` | String | `warning` | Xray 日志级别 |
| `routingMode` | String | `rule` | `rule`、`global`、`direct` |
| `systemProxyEnabled` | Bool | `false` | Xray 运行期间是否发布 macOS 系统代理 |

解码旧文件时，缺少 `routingMode` 和 `systemProxyEnabled` 分别回退为 `rule` 和 `false`。操作系统代理状态不写入服务器配置；`systemProxyEnabled` 只是用户偏好，实际状态由 `SystemProxyManager` 与快照共同决定。

默认资源只在目标不存在时复制。升级时只有与历史默认内容 SHA-256 完全匹配的文件才会迁移，用户编辑过的资源必须保留。迁移会先清理可再生成的派生文件，再原子替换来源文件，以保持失败后可重试。

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
                         ┌─ rule/global ─ server.json + 当前选择的 IP
local-proxy.json + 模式 ─┤
                         └─ direct ────── 不依赖服务器或节点
  → 合成 template.json 兼容镜像
  → 生成 config.json（原子写入，0600）
  → Xray `run -test`
  → 启动仅监听回环地址的 mixed 入站
```

三种路由模式的运行时语义为：

- `rule`：默认加入 `geoip:private → direct` 基础规则，基础配置的其余连接使用 `proxy` 出站；关闭 `bypassPrivateNetworks` 时不加入该基础规则。高级完整 JSON 中的非 ViaSix 管理规则会保留，并按其原有顺序参与路由。
- `global`：生成 `tcp,udp → proxy` 兜底规则，要求有效服务器配置和当前节点。
- `direct`：生成 `tcp,udp → direct` 兜底规则，并从运行配置移除 `proxy` 出站；不要求 `server.json` 或当前节点，但仍需 Xray 提供本地 mixed 入站。

在 `rule` 和 `global` 模式中，ViaSix 只修改 `tag == "proxy"` 的第一个 `settings.vnext.address` 或 `settings.servers.address`。配置时会校验：

- `rule` / `global` 的服务器配置包含非空 `proxy` 出站，以及可用的 `vnext` 或 `servers`。
- `direct` 包含可用的 `direct`/`freedom` 出站与明确的全直连路径。
- 本机配置只监听回环地址，并使用有效端口。
- 合成配置包含回环 `mixed` 入站，应用用其实际主机和端口进行就绪探测和出口检测。
- 服务器模式启动时不再包含中性 UUID 或示例域名占位符。

节点切换以成功写入派生配置为运行时提交点。偏好保存失败会记录警告并重试，但不阻止正在运行的 Xray 应用新节点。

## 系统代理生命周期

系统代理是独立于 Xray 路由模式的网络接入层，由 actor 隔离的 `SystemProxyManager` 通过公开的 macOS SystemConfiguration API 管理，不执行 `networksetup` 等 shell 命令。

启用流程：

1. 仅在 Xray 本地 mixed 入站启动成功且 `systemProxyEnabled == true` 时继续。
2. 读取所有当前启用的 macOS 网络服务，并在任何服务不支持代理协议时于修改前整体失败。
3. 保存每个服务完整的原始代理属性列表、协议启用状态和 ViaSix 将应用的目标值到 `Data/system-proxy.json`。
4. 在持有 SystemConfiguration 偏好锁时检查前置状态，并以一次事务把 HTTP、HTTPS 和 SOCKS 指向当前本地端点。
5. 保留旁路列表、PAC URL 与未知键，但在会话期间把 `ProxyAutoConfigEnable` 设为 `0`，避免 PAC 与固定代理同时生效。

恢复流程：

- 用户关闭系统代理、停止 Xray 或退出 ViaSix 时，先比较当前设置与 ViaSix 曾应用的值；未被外部修改的服务恢复为完整原始属性列表。
- 其他应用或用户已经修改的服务不会被旧快照覆盖；不存在的服务也只记录报告。
- Xray 意外退出会触发异步恢复；进程崩溃或强制终止留下的快照会在下次应用启动时恢复。
- 应用系统代理失败时执行尽力回滚。正常停止时若恢复失败，`AppModel` 优先保留仍可用的本地监听，避免系统应用继续指向已关闭端口。

系统代理偏好和实际状态分离。保存 `systemProxyEnabled == true` 不代表操作系统此刻已启用代理；只有 Xray 处于运行状态且系统配置事务成功时，UI 才报告已启用。

## 网络接入边界

路由模式决定“进入本地 mixed 入站之后如何出站”，系统代理决定“遵循 macOS 代理设置的应用是否自动进入该入站”。这两个维度都不会捕获忽略系统代理的进程或任意系统数据包。

当前版本没有虚拟网卡/TUN、默认路由接管或 DNS 重写能力，也不安装 Network Extension 或系统扩展。后续如实现虚拟网卡，应作为独立能力边界处理权限、上游服务器绕行、路由与 DNS 的原子恢复、崩溃恢复和可用性检测，不能把系统代理开关或现有三种 Xray 路由模式当作 TUN 状态。

## 运行组件安装

官方安装流程按 CPU 架构选择上游最新正式版资产：

1. 查询两个上游仓库的 GitHub latest Release 元数据。
2. 按当前架构匹配 macOS 资产，并要求 Release 提供 SHA-256 digest。
3. 从 GitHub HTTPS URL 下载到临时目录并重新计算 SHA-256。
4. 解压并确认所有必要 payload。
5. 在完整验证后原子移动到 `Runtime/`。

源码中的固定清单是可审计基线和测试夹具，不再决定在线安装版本。GitHub 元数据缺少目标资产或 digest 时安装会失败，不会绕过完整性检查。

自定义路径优先于 ViaSix 管理副本，其后依次查找 Homebrew 常用目录和当前 `PATH`。本地导入组件由用户自行信任。

## 进程与并发边界

- UI 和 `AppModel` 保持在 `@MainActor`。
- CFST、Xray、系统代理、偏好和组件管理使用 actor 隔离。
- 每个会改变外部状态的长任务都由 `AppModel` 持有；退出时先取消，再停止自有进程并等待任务收敛。
- ViaSix 从不按进程名全局结束进程，只向自己创建并仍持有的 PID / 进程组发送信号。
- Xray 启动包含配置校验、端口占用检查、就绪探测、超时、异常退出和清理路径。

## 信任边界

| 输入或组件 | 信任方式 | 主要风险 |
| --- | --- | --- |
| 内置资源 | 随应用源码和签名发布 | 错误默认值、迁移覆盖 |
| 在线运行组件 | GitHub latest Release、资产命名规则和 SHA-256 digest | 上游供应链、许可证变化 |
| 本地导入组件 | 用户明确选择 | 恶意或架构不兼容二进制 |
| Xray JSON | 结构和回环监听校验 | 凭据泄露、错误服务器配置 |
| macOS 网络代理设置 | SystemConfiguration 锁、前置状态比较和恢复快照 | 权限失败、外部并发修改、异常退出遗留 |
| 自定义 IP / CIDR / URL | 参数校验后交给 CFST | 过量网络负载、不可信目标 |
| 出口 IP 服务 | 用户可配置的 HTTP / HTTPS 响应并验证 IP 格式 | 可用性、第三方日志和错误数据 |

## 分发模型

当前设计面向 Developer ID 签名、公证和非 Mac App Store 分发。应用需要在 Application Support 中运行外部网络工具，并可在用户启用后修改 macOS 网络代理设置，因此不适合现有 Mac App Store 沙盒模型。

开发运行使用 SwiftPM 的 `Bundle.module` 读取资源。打包构建定义 `VIASIX_PACKAGED_APP`，只从 `Bundle.main` 读取资源并启用 dead stripping，避免把本机 SwiftPM 资源路径带入分发二进制。应用包验证会扫描本地检出路径和必需资源。
