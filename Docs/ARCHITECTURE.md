# ViaSix 架构说明

本文描述 ViaSix 的模块边界、数据流、信任边界和进程生命周期。终端用户请从 [README](../README.md) 或[用户指南](USER_GUIDE.md)开始。

## 目录

- [总体结构](#总体结构)
- [启动与恢复](#启动与恢复)
- [可写数据](#可写数据)
- [节点测速流程](#节点测速流程)
- [代理配置流程](#代理配置流程)
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
2. 加载用户偏好并规范化内置地址列表路径。
3. 加载运行组件状态。
4. 尝试加载最近测速结果和派生 Xray 配置。
5. 进入可用界面。

目录或默认资源无法准备属于致命启动错误。损坏的 `result.csv` 属于可丢弃缓存，不阻止启动；损坏的代理模板或派生配置会记录警告并允许用户从“设置”重新导入或编辑。

## 可写数据

签名后的应用 bundle 始终按只读处理。可变数据位于：

```text
~/Library/Application Support/ViaSix/
  Data/
    preferences.json
    ip.txt
    ipv6.txt
    template.json
    config.json
    result.csv
  Runtime/
    cfst
    xray
    geoip.dat
    geosite.dat
  Logs/
```

目录权限为 `0700`，ViaSix 管理的偏好、列表和配置文件权限为 `0600`。`template.json` 是用户连接资料的来源；`config.json` 是按当前节点生成的派生文件，可以重新创建。

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
template.json
  + 当前选择的 IP
  → ConfigTemplate.replacingAddress
  → config.json（原子写入，0600）
  → Xray `run -test`
  → 启动本地 mixed 入站
```

ViaSix 只修改 `tag == "proxy"` 的第一个 `settings.vnext.address`。导入模板时会校验：

- 所有入站只监听回环地址。
- 存在端口有效的回环 `mixed` 入站；应用从该入站读取实际主机和端口，并将其用于就绪探测和出口检测。
- 存在非空 `outbounds`、`proxy` 出站和 `vnext`。
- 启动时不再包含中性 UUID 或示例域名占位符。

节点切换以成功写入派生配置为运行时提交点。偏好保存失败会记录警告并重试，但不阻止正在运行的 Xray 应用新节点。

## 运行组件安装

官方安装流程按 CPU 架构选择固定资产：

1. 从固定 HTTPS URL 下载到临时目录。
2. 校验清单中固定的 SHA-256。
3. 解压并确认所有必要 payload。
4. 在完整验证后原子移动到 `Runtime/`。

自定义路径优先于 ViaSix 管理副本，其后依次查找 Homebrew 常用目录和当前 `PATH`。本地导入组件由用户自行信任。

## 进程与并发边界

- UI 和 `AppModel` 保持在 `@MainActor`。
- CFST、Xray、偏好和组件管理使用 actor 隔离。
- 每个会改变外部状态的长任务都由 `AppModel` 持有；退出时先取消，再停止自有进程并等待任务收敛。
- ViaSix 从不按进程名全局结束进程，只向自己创建并仍持有的 PID / 进程组发送信号。
- Xray 启动包含配置校验、端口占用检查、就绪探测、超时、异常退出和清理路径。

## 信任边界

| 输入或组件 | 信任方式 | 主要风险 |
| --- | --- | --- |
| 内置资源 | 随应用源码和签名发布 | 错误默认值、迁移覆盖 |
| 在线运行组件 | 固定 URL、版本和 SHA-256 | 上游供应链、许可证变化 |
| 本地导入组件 | 用户明确选择 | 恶意或架构不兼容二进制 |
| Xray JSON | 结构和回环监听校验 | 凭据泄露、错误服务器配置 |
| 自定义 IP / CIDR / URL | 参数校验后交给 CFST | 过量网络负载、不可信目标 |
| 出口 IP 服务 | 用户可配置的 HTTP / HTTPS 响应并验证 IP 格式 | 可用性、第三方日志和错误数据 |

## 分发模型

当前设计面向 Developer ID 签名、公证和非 Mac App Store 分发。应用需要在 Application Support 中运行外部网络工具，因此不适合现有 Mac App Store 沙盒模型。

开发运行使用 SwiftPM 的 `Bundle.module` 读取资源。打包构建定义 `VIASIX_PACKAGED_APP`，只从 `Bundle.main` 读取资源并启用 dead stripping，避免把本机 SwiftPM 资源路径带入分发二进制。应用包验证会扫描本地检出路径和必需资源。
