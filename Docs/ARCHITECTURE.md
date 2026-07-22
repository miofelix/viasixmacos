# ViaSix 架构说明

本文描述 ViaSix 的 IPv6-first 运行模型、配置投影、独立网络接入控制和特权 TUN 信任边界。

## 总体结构

```text
ViaSixApp（SwiftUI / @MainActor）
  首页 · IPv6 优选 · 连接配置 · 日志 · 设置
                    │
          ┌─────────┴──────────┐
          ▼                    ▼
ViaSixCore               ViaSixMihomoConfig
状态持久化 / CFST /       YAML 解析 / IPv6 投影 /
用户态 Mihomo / 系统代理  特权 envelope
          │                    │
          └─────────┬──────────┘
                    ▼
ViaSixPrivilegedProtocol → ViaSixTunHelper → 固定签名 Mihomo
```

- `ViaSixApp`：窗口、菜单栏和工作流编排；
- `AppModel`：主线程唯一状态协调者，管理任务取消、启停和就绪判断；
- `ViaSixCore`：资源、偏好、测速、用户态 Mihomo 和系统代理；
- `ViaSixMihomoConfig`：安全解析、IPv6 运行投影和特权 envelope；
- `ViaSixPrivilegedProtocol`：App 与 helper 共用的版本化 typed XPC 协议；
- `ViaSixTunHelper`：验证调用者后只启动应用内固定签名 Mihomo。

## 产品不变量

ViaSix 没有兼容模式，也不迁移旧 Xray 配置。

规则或全局模式启动前必须满足：

```text
selectedIP 是 IPv6
    ∧ profile 有可替换的内联主代理
    ∧ 选择的运行方式已就绪
```

直连模式不要求节点或 profile，生成 `MATCH,DIRECT`。

`routingMode` 与网络接入相互独立：

- `routingMode`：`rule`、`global`、`direct`；
- `networkAccessMode`：`localProxy` 或 `virtualInterface`；
- `systemProxyEnabled`：独立的 macOS 系统代理偏好。

因此系统代理和 TUN 可以同时启用。旧 `systemProxy` 网络接入枚举不再解码。

## 配置来源

```text
preferences.json  当前 IPv6 和测速偏好
profile.yaml       用户导入的 Mihomo 服务器配置
local-proxy.json   代理模式、网络开关、本地监听和 TUN 参数
```

`local-proxy.json` 的关键字段：

| 字段 | 新安装默认 | 说明 |
| --- | --- | --- |
| `listenAddress` | `127.0.0.1` | 只允许回环地址 |
| `port` | `11451` | mixed 端口 |
| `controllerPort` | `9090` | 回环 Controller 端口 |
| `routingMode` | `rule` | 规则、全局或直连 |
| `networkAccessMode` | `virtualInterface` | 用户态本地运行或特权 TUN |
| `systemProxyEnabled` | `false` | 独立系统代理开关 |
| `tunStack` | `mixed` | Mixed/System/gVisor |
| `tunMTU` | `1500` | 1280–9000 |

已移除 `ipv6TransportPolicy`。运行时策略始终是 IPv6-first。

## Mihomo 运行投影

规则模式：

```text
profile.yaml
  → 找到第一个可替换 server 的内联代理
  → 验证 selectedIP 为 IPv6
  → 只保留该代理并替换 server
  → 删除 Provider、代理组、规则 Provider、子规则和导入规则
  → 写入私有/回环/链路本地 DIRECT 规则
  → 追加 MATCH,<primary proxy>
```

全局模式使用相同的单 IPv6 主代理，Mihomo `mode` 为 `global`，不保留导入规则。

直连模式不复制代理、Provider、代理组或远端规则：

```yaml
mode: direct
rules:
  - MATCH,DIRECT
```

Provider-only 配置和 IPv4 选择在用户态、特权 TUN 两条路径中都会被拒绝。

`x-viasix` 只允许：

```yaml
x-viasix:
  version: 1
  primary-server: selected-ip
```

它不能覆盖代理模式、系统代理、TUN、监听、日志、嗅探、UDP 或 DNS。

## 启动与可恢复错误

启动流程：

1. 准备 Application Support、默认资源和 Controller 密钥；
2. 恢复可能遗留的系统代理快照；
3. 加载偏好、测速结果、连接配置和本机配置；
4. 同步可重新生成的用户态配置；
5. 检查 TUN helper、固定 Mihomo 和现有会话；
6. 发布 `AppState` 并进入可交互状态。

下列情况属于可恢复的就绪问题：

- 未选择 IPv6 或选择了 IPv4；
- profile 只有 Provider 或无可替换内联代理；
- 请求 TUN 但服务、固定运行时或功能集未就绪；
- 关闭 TUN 后没有可用的用户态 Mihomo。

就绪提示优先报告配置问题，然后报告 IPv6 节点，最后报告所选运行方式，以便用户按实际顺序修复。

## 系统代理与 TUN

系统代理和 TUN 由不同状态机管理：

- `systemProxyEnabled` 表示用户偏好；`systemProxyPhase` 表示 macOS 当前实际状态；
- `networkAccessMode == virtualInterface` 表示启动特权 TUN；
- 切换 TUN 会停止当前运行时、保存偏好并启动新运行时；
- TUN 切换不改变系统代理偏好；
- 系统代理可在 TUN 运行期间独立启停；
- 停止、异常退出和应用退出都必须恢复系统代理。

## TUN 信任边界

应用不会把用户可写 YAML 直接交给 root-owned Mihomo：

1. App 先生成只含单 IPv6 主代理或直连规则的安全投影；
2. 投影结果与规范化选项编码为 binary plist envelope；
3. helper 检查大小、深度、复杂度、schema 和规范形式；
4. helper 从 envelope 重建配置并再次执行特权白名单；
5. 只有重建结果与 canonical envelope 一致时才生成运行 YAML。

直连 envelope 不携带任何服务器映射。helper 不能执行用户目录中的二进制，也不能接收路径、argv、shell 或原始 YAML。

## Controller 与日志

Controller 固定监听 `127.0.0.1`，使用 `Data/Mihomo/controller.secret` 中的随机 Bearer 密钥。导入 YAML 中的 Controller 字段不会进入运行配置。

ViaSix 不读取 Clash Selector 代理组，不订阅 `/connections`，也不轮询规则、Provider、流量或内存。

日志不是 Controller 仪表盘，而是独立诊断通道。应用、测速、代理、系统代理和 TUN 事件统一进入 `AppState.logs`，日志页面负责筛选、排序、跟随和清空。

## 数据布局

```text
~/Library/Application Support/ViaSix/
  Data/
    preferences.json
    ipv4.txt
    ipv6.txt
    profile.yaml
    local-proxy.json
    result.csv
    system-proxy.json
    Mihomo/
      config.yaml
      controller.secret
  Runtime/
    cfst
    mihomo
  Logs/
```

目录权限为 `0700`，配置和偏好文件为 `0600`。`Mihomo/config.yaml` 是派生文件。

## 并发与恢复

- UI 和 `AppModel` 位于 `@MainActor`；
- CFST、Mihomo、偏好、系统代理和 TUN 协调器使用 actor 隔离；
- 长任务由 `AppModel` 持有并在停止、重启或退出时取消；
- ViaSix 只终止自己创建并仍持有身份的进程或进程组；
- 系统代理恢复和 TUN 停止在退出完成前收敛，失败时拒绝假装安全退出。
