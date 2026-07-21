# ViaSix 开发说明

本文面向 ViaSix 的开发者和贡献者。终端用户请阅读 [README](../README.md) 和 [用户指南](USER_GUIDE.md)。

## 目录

- [开发环境](#开发环境)
- [构建与运行](#构建与运行)
- [测试与验证](#测试与验证)
- [工程结构](#工程结构)
- [运行组件](#运行组件)
- [内置地址列表](#内置地址列表)
- [可写数据与资源](#可写数据与资源)
- [默认资源与迁移](#默认资源与迁移)
- [Mihomo 配置流程](#mihomo-配置流程)
- [进程与并发约定](#进程与并发约定)
- [虚拟网卡开发边界](#虚拟网卡开发边界)
- [测速结果约定](#测速结果约定)
- [文档职责](#文档职责)

## 开发环境

- macOS 15.2 或更高版本（开发环境；应用运行最低要求仍为 macOS 14）
- Xcode 16.3 或更高版本
- Swift 6.1 或更高版本
- zsh、make 以及 macOS 自带的签名和打包工具

确认工具链：

```bash
swift --version
xcodebuild -version
```

## 构建与运行

调试构建：

```bash
make build
```

直接运行 SwiftPM 可执行目标：

```bash
swift run ViaSix
```

Release 构建：

```bash
swift build -c release
```

生成可双击运行的应用：

```bash
make app
open dist/ViaSix.app
```

`make app` 默认生成优化后的 ad-hoc 签名包，`make app-debug` 生成调试包，均适用于本地开发与冒烟测试。打包时会取得当前架构的固定 Mihomo v1.19.29；已有上游二进制时可设置 `VIASIX_MIHOMO_SOURCE=/absolute/path/to/mihomo`，但大小、SHA-256、Mach-O 架构和版本校验不会因此放宽。正式签名和公证流程见[发布指南](RELEASING.md)。

打包脚本会定义 `VIASIX_PACKAGED_APP`，使 app bundle 只从 `Bundle.main` 读取默认资源，避免 SwiftPM 的开发期 `Bundle.module` 路径泄露本机检出目录。修改资源加载或打包命令时必须保留对应验证。

## 测试与验证

统一格式化 Swift 源码：

```bash
make format
```

运行格式、脚本语法、元数据、文档链接和许可证检查：

```bash
make lint
```

运行全部测试：

```bash
make test
```

验证已生成的应用包：

```bash
make verify-app
```

运行与 CI 一致的 Release 严格构建和全部测试：

```bash
make check
```

`make test` 和 `make check` 都会把 Swift 编译警告视为错误。

`make clean` 只清理仓库中的 SwiftPM 和 `dist` 构建产物，不会删除 `~/Library/Application Support/ViaSix` 中的用户数据：

```bash
make clean
```

## 工程结构

```text
Sources/
  ViaSixMihomoConfig/       Mihomo YAML、Profile、分享链接与旧配置迁移
  ViaSixCore/
    Configuration/          本机代理设置和兼容配置逻辑
    Infrastructure/         路径、默认资源、启动、系统代理与接入能力
    Models/                 测速参数、结果和用户偏好
    Networking/             出口 IP 检测
    Parsing/                CSV 与 CFST 流式输出解析
    Resources/              默认地址列表和本机代理设置
    Runtime/                固定组件安装、CFST 与 Mihomo 生命周期
  ViaSixApp/
    App/                    应用入口、生命周期与内置文档
    DesignSystem/           视觉样式
    Features/               首页、节点、日志、设置和菜单栏
    State/                  AppModel 与应用状态
  ViaSixPrivilegedProtocol/ app/helper 共用的固定 XPC 协议
  ViaSixTunHelperSupport/   helper 身份校验和会话恢复支撑
  ViaSixTunHelper/          SMAppService LaunchDaemon 可执行程序
Tests/                      各目标单元和集成测试
Packaging/                  Info.plist、entitlements、LaunchDaemon plist 与图标
Scripts/                    图标、应用打包、文档链接与 bundle 验证
Docs/                       用户、开发、架构与发布文档
ThirdPartyLicenses/         固定上游版本的许可证原文
```

SwiftPM 的主要边界：

- `ViaSixMihomoConfig` 只负责 Mihomo 配置语义，不依赖 SwiftUI。
- `ViaSixCore` 负责平台逻辑和用户态进程，不应反向依赖 App target。
- `ViaSixApp` 负责呈现与工作流编排。
- `ViaSixPrivilegedProtocol` 只暴露固定 typed XPC 协议，不能接受路径、argv、shell 或任意 YAML。
- `ViaSixTunHelperSupport` 与 `ViaSixTunHelper` 保持最小特权面；当前没有真实 TUN 后端。

更详细的模块关系见[架构说明](ARCHITECTURE.md)。

## 运行组件

普通用户运行组件的版本、下载地址、目标架构、压缩格式、压缩包哈希和 payload 预期位于：

```text
Sources/ViaSixCore/Runtime/RuntimeManifest.swift
```

当前固定组件：

- CloudflareSpeedTest `v2.3.5`
- Mihomo `v1.19.29`

应用包中的特权 Mihomo 由 `Scripts/fetch-mihomo.sh` 独立准备。该脚本与 `RuntimeManifest.swift` 必须保持同一版本、资产 URL、压缩包 SHA-256、payload 大小和 SHA-256；它还会拒绝错误 Mach-O 架构或版本输出。签名后的文件固定放在 `Contents/Library/HelperTools/com.felix.viasix.mihomo`，完整摘要和 CDHash 写入由外层 app seal 保护的 `Contents/Resources/PrivilegedRuntime.plist`。

组件解析优先级：

1. 用户偏好中的自定义可执行路径
2. ViaSix 管理的 `Runtime` 副本
3. `/opt/homebrew/bin`
4. `/usr/local/bin`
5. 当前进程的 `PATH`

在线安装流程（CFST 与 Mihomo 可分别执行）：

1. 从固定清单选择当前 CPU 架构对应的 HTTPS 资产，不查询 GitHub `latest`。
2. 下载到临时目录并核对压缩包 SHA-256。
3. 用受限 ZIP/GZIP 解压器提取清单声明的 payload。
4. 核对解压后文件大小、SHA-256 和可执行属性。
5. 完整验证后事务性替换所选 payload，并原样保留另一个受管组件；任何失败都保留旧的可用副本。

设置页中的“导入”表示为对应组件选择自定义可执行文件路径，不会复制到受管 Runtime。Mihomo 管理副本只需要 `mihomo` 可执行文件；其 home、Provider 缓存和规则数据位于 `Data/Mihomo/`。旧 `xray`、`geoip.dat` 与 `geosite.dat` 不是当前组件，成功安装 Mihomo 后会从受管 Runtime 中清理。

更新固定清单时，必须同时：

- 更新 `RuntimeManifest.swift` 的版本、URL、资产名、压缩格式和双重校验值
- 同步更新 `Scripts/fetch-mihomo.sh` 的嵌入资产清单与打包验签预期
- 更新测试中的预期值
- 更新[第三方声明](../THIRD_PARTY_NOTICES.md)和离线许可证
- 在 arm64 与 x86_64 对应环境验证下载、校验和启动
- 确认旧 Runtime 在新资产校验失败时仍可用

CloudflareSpeedTest 是 XIU2 维护的独立第三方项目，并非 Cloudflare 官方产品。“上游组件”表示从各项目自己的正式 Release 获取。

## 内置地址列表

`ip.txt` 和 `ipv6.txt` 的来源、快照日期、文件哈希及更新步骤统一记录在[内置地址列表来源](ADDRESS_SOURCES.md)。更新默认列表时还必须增加精确匹配迁移，不能直接覆盖用户已经编辑的副本。

## 可写数据与资源

应用 bundle 始终按只读处理。可变数据位于：

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
      providers/
      rules/
  Runtime/
    cfst
    mihomo
  Logs/
```

文件职责：

- `preferences.json`：`Codable` 用户偏好；新增字段应提供向后兼容默认值。`mihomoPath` 与历史 `xrayPath` 不兼容，不能自动复制。
- `ip.txt` / `ipv6.txt`：复制到用户目录后的地址源。
- `profile.yaml`：用户维护的 Mihomo 节点、Provider、代理组和规则，不包含本机监听设置。
- `local-proxy.json`：本机监听地址、端口、UDP、嗅探、私网直连、代理模式和互斥的网络接入方式。
- `Mihomo/config.yaml`：按当前模式生成的运行配置，不是配置的唯一来源。
- `Mihomo/providers/` / `Mihomo/rules/`：HTTP Provider 的受控相对路径和缓存。
- `system-proxy.json`：系统代理会话恢复快照。
- `result.csv`：当前测速输出；启动新任务前删除。
- `Runtime`：ViaSix 管理的第三方可执行组件。
- `Logs`：为未来持久日志预留；当前界面日志仅在内存中。

ViaSix 会把目录权限收紧为 `0700`，把偏好、地址列表和代理配置等管理文件收紧为 `0600`。新增写入路径时必须保持相同边界；不要依赖用户默认 `umask` 保护敏感配置。

## 默认资源与迁移

`DefaultResourceInstaller` 负责首次复制和安全迁移：

- 目标文件不存在时，从 bundle 复制 `ip.txt`、`ipv6.txt` 和 `local-proxy.json`。
- 已存在文件只有在 SHA-256 与历史默认版本完全一致时才会迁移。
- 用户修改过的地址列表和本机设置必须保留。
- 旧版 `server.json` 优先于 `template.json` 作为只读迁移输入；支持的单节点 Xray JSON 转换为 Mihomo `profile.yaml`。
- 旧 JSON 保留用于用户回退和人工核对，不作为当前运行配置。
- 旧 `config.json` 是可丢弃派生文件；当前运行配置只写入 `Data/Mihomo/config.yaml`。

增加新的默认资源迁移时，应：

1. 固定历史资源的准确哈希。
2. 为完全匹配、用户已修改、目标缺失和派生文件清理分别增加测试。
3. 不使用文件名、修改时间或模糊内容匹配覆盖用户文件。
4. 保证失败可重试，并且不会执行旧内核路径。

## Mihomo 配置流程

`MihomoServerConfiguration` 接受 UTF-8 YAML，限制文档大小、深度和复杂度，并只保留服务器侧键：

- `proxies`
- `proxy-providers`
- `proxy-groups`
- `rules`
- `rule-providers`
- `sub-rules`

本机监听、端口、日志、嗅探、UDP、代理模式和网络接入方式必须来自 `local-proxy.json`，不能由导入的服务器 YAML 覆盖。所有运行配置固定 `allow-lan: false`，监听地址必须是回环地址。

配置流向：

```text
profile.yaml + local-proxy.json + 当前模式
    + 可选的当前测速节点
    ↓
MihomoServerConfiguration.runtimeConfiguration
    ↓
Data/Mihomo/config.yaml（原子写入）
    ↓
mihomo -t -d Data/Mihomo -f Data/Mihomo/config.yaml
    ↓
Mihomo 用户态运行
```

重要语义：

- `rule` / `global` 需要内联 `proxies` 或 `proxy-providers`；Provider-only 配置不需要当前测速节点。
- 当前测速节点存在时，只替换第一个内联节点的 `server`；没有当前节点时保留原地址。
- `direct` 不复制代理、Provider、代理组或远端规则，生成 `MATCH,DIRECT`，避免订阅刷新和上游握手。
- HTTP Provider 的 `path` 被改写到 `providers/` 或 `rules/`；inline Provider 不落任意外部路径；其他 Provider 类型被拒绝。
- 表单支持 VLESS、VMess、Trojan 和 Shadowsocks；高级编辑器用于多节点、Provider、代理组和规则。
- 旧 Xray JSON 仅通过 `LegacyXrayConfigurationMigrator` 转换受支持的单节点结构，不直接交给 Mihomo。

修改配置模型时，应覆盖原生 YAML 往返、Provider-only、内联节点覆盖、无节点保留、direct 去远端依赖、旧 JSON 迁移失败和 Mihomo 自身 `-t` 校验。

## 进程与并发约定

- CFST 与 Mihomo 均由各自 actor 管理完整生命周期。
- 系统代理和虚拟网卡能力边界也必须通过独立 actor/协议隔离；不得把特权路由操作放进 SwiftUI 或普通用户态流程。
- ViaSix 只停止自己创建并仍持有的子进程，不允许按进程名进行全局 kill。
- 子进程使用独立进程组；取消任务时清理其完整进程组。
- 读取 stdout / stderr 时保持流式处理并等待 EOF。
- 应用退出时取消未完成任务，恢复系统代理，停止自有进程并保存偏好。
- UI 状态编排保持在 `@MainActor AppModel`。

修改生命周期代码时，应覆盖配置校验、启动、取消、异常退出、端口冲突、超时、重复调用、系统代理回滚和应用退出场景。

## 虚拟网卡开发边界

`NetworkAccessMode` 已定义本地代理、系统代理和虚拟网卡三个互斥值，但当前配置生成和应用启动对 `virtualInterface` fail closed，UI 控制项不可用。Mihomo YAML 生成器具备受约束的 `tun` 配置模型，不代表应用已经具备安全启用条件。

真实 TUN 前必须满足[虚拟网卡能力边界](VIRTUAL_NETWORK.md)中的签名、特权、路由、DNS、进程监督和崩溃恢复要求。尤其是：

- helper 不能执行用户可写的 `Runtime/mihomo`。
- XPC 不能接收路径、argv、shell 或原始 YAML。
- 特权执行必须使用固定、root-owned、已签名的 Mihomo，并直接 `posix_spawn`。
- journal 必须能精确识别会话进程、utun、路由、DNS 和配置摘要；不能用空 cleanup 宣告恢复成功。
- 系统代理与 TUN 的切换必须由同一 `NetworkAccessMode` 状态机协调。

## 测速结果约定

- 新测速开始前删除旧 `result.csv`。
- 只解析本次进程成功生成的结果。
- CSV 和控制台输出解析应兼容 CRLF、分段 UTF-8 和无尾换行。
- 空结果、缺少结果文件和非零退出需要区分错误原因。
- 参数校验和 CLI 参数映射由单元测试覆盖。

## 文档职责

- `README.md`：产品主页和最短上手路径，只放用户需要的信息。
- `Docs/USER_GUIDE.md`：详细使用、配置、备份和排错。
- `Docs/DEVELOPMENT.md`：构建、测试、目录、数据和开发约定。
- `Docs/ARCHITECTURE.md`：模块和进程边界。
- `Docs/VIRTUAL_NETWORK.md`：虚拟网卡能力、权限和恢复边界。
- `Docs/RELEASING.md`：签名、公证和发布检查。
- `Docs/ADDRESS_SOURCES.md`：默认地址列表来源、快照和更新流程。
- `CONTRIBUTING.md`：Issue / PR、提交、测试和文档同步规则。
- `CHANGELOG.md`：用户可见变化和版本历史。
- `SECURITY.md`：私密漏洞报告与供应链约定。
- `PRIVACY.md`：本机数据、网络端点、保留与删除方式。
- `THIRD_PARTY_NOTICES.md`：第三方版本、来源和许可证义务。
- `LICENSE`：ViaSix 自身的 MIT 授权条款。

产品历史或内部验收对照不应出现在用户文档和应用文案中。
