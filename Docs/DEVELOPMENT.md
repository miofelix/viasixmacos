# ViaSix 开发说明

本文面向 ViaSix 的开发者和贡献者。终端用户请阅读 [README](../README.md) 和 [用户指南](USER_GUIDE.md)。

## 开发环境

- macOS 14 Sonoma 或更高版本
- Xcode 16.3 或更高版本
- Swift 6.1
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

`make app` 默认生成 ad-hoc 签名包，适用于本地开发与冒烟测试。正式签名和公证流程见 [发布指南](RELEASING.md)。

## 测试与验证

运行全部测试：

```bash
make test
```

验证已生成的应用包：

```bash
make verify-app
```

需要把编译警告视为错误时：

```bash
swift build -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
```

`make clean` 只清理仓库中的 SwiftPM 和 `dist` 构建产物，不会删除 `~/Library/Application Support/ViaSix` 中的用户数据：

```bash
make clean
```

## 工程结构

```text
Sources/
  ViaSixCore/
    Configuration/    Xray 模板验证与配置生成
    Infrastructure/   路径、默认资源、启动准备与偏好存储
    Models/           测速参数、结果和用户偏好
    Networking/       出口 IP 检测
    Parsing/          CSV 与 CFST 流式输出解析
    Resources/        默认地址列表和中性 Xray 模板
    Runtime/          组件安装、CFST 与 Xray 生命周期
  ViaSixApp/
    App/              应用入口和生命周期
    DesignSystem/     视觉样式
    Features/         总览、节点、日志、设置和菜单栏
    State/            AppModel 与应用状态
Tests/
  ViaSixCoreTests/    核心逻辑与进程行为测试
  ViaSixAppTests/     应用状态编排和配置一致性测试
Packaging/            Info.plist 与应用图标源文件
Scripts/              图标、应用打包与 bundle 验证
Docs/                 用户、开发、架构与发布文档
```

SwiftPM 定义两个主要目标：

- `ViaSixCore`：可导入的核心库，不依赖 SwiftUI。
- `ViaSixApp`：原生 SwiftUI macOS 可执行程序。

更详细的模块关系见 [架构说明](ARCHITECTURE.md)。

## 运行组件

运行组件版本、下载地址、目标架构和 SHA-256 位于：

```text
Sources/ViaSixCore/Runtime/RuntimeManifest.swift
```

当前组件：

- CloudflareSpeedTest `v2.3.5`
- Xray-core `v26.3.27`

组件解析优先级：

1. 用户偏好中的自定义可执行路径
2. ViaSix 管理的 `Runtime` 副本
3. `/opt/homebrew/bin`
4. `/usr/local/bin`
5. 当前进程的 `PATH`

在线安装流程：

1. 按当前 CPU 架构选择固定资产。
2. 通过 HTTPS 下载到临时目录。
3. 校验固定 SHA-256。
4. 解压并确认必要文件完整。
5. 将完整组件移动到应用数据目录。

本地导入支持可执行文件、目录或多个相关文件。Xray 管理副本需要 `xray`、`geoip.dat` 和 `geosite.dat`。

更新组件版本时，必须同时：

- 更新 `RuntimeManifest.swift` 的版本、URL、资产名和哈希
- 更新测试中的预期值
- 更新 [第三方声明](../THIRD_PARTY_NOTICES.md)
- 在 arm64 与 x86_64 对应环境验证下载和启动

## 可写数据与资源

应用 bundle 始终按只读处理。可变数据位于：

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

文件职责：

- `preferences.json`：`Codable` 用户偏好，新增字段应提供向后兼容默认值。
- `ip.txt` / `ipv6.txt`：复制到用户目录后的地址源。
- `template.json`：用户维护的代理连接模板。
- `config.json`：由模板和当前节点生成，不是配置的唯一来源。
- `result.csv`：当前测速输出；启动新任务前删除。
- `Runtime`：ViaSix 管理的第三方组件。
- `Logs`：为未来持久日志预留；当前界面日志仅在内存中。

## 默认资源与迁移

`DefaultResourceInstaller` 负责首次复制和安全迁移：

- 目标文件不存在时，从 bundle 复制默认资源。
- 已存在文件只有在 SHA-256 与某个历史默认版本完全一致时才会迁移。
- 用户修改过的地址列表或代理模板必须保留。
- 旧版默认 IPv4 列表可迁移到完整列表。
- 旧版内置连接模板可迁移为不含真实连接资料的中性模板。
- 迁移模板时会移除由旧模板生成的 `config.json`，避免继续使用旧连接资料。

增加新的默认资源迁移时，应：

1. 固定历史资源的准确哈希。
2. 为完全匹配、用户已修改、目标缺失和派生文件清理分别增加测试。
3. 不使用文件名、修改时间或模糊内容匹配覆盖用户文件。

## Xray 配置流程

默认模板和导入模板必须满足：

- 根对象是有效 JSON。
- 包含非空 `outbounds`。
- 存在 `tag == "proxy"` 的出站。
- `proxy.settings.vnext` 非空。

配置流向：

```text
template.json
    + 当前选择的 IP
    ↓
ConfigTemplate.replacingAddress
    ↓
config.json（原子写入）
    ↓
启动前占位符检查与 xray run -test
    ↓
Xray 运行
```

ViaSix 只替换 `proxy` 出站中第一个 `vnext.address`。导入新模板时先校验结构，再以原子写入替换用户模板；已有选中节点时同步重新生成 `config.json`。

中性模板使用明确占位符。启动前若仍存在默认 UUID 或示例域名，应返回面向用户的“连接尚未配置”错误。

## 进程与并发约定

- CFST 与 Xray 均由各自 actor 管理完整生命周期。
- ViaSix 只停止自己创建并仍持有的子进程。
- 不允许按进程名进行全局 kill。
- CFST 使用独立进程组，取消任务时应清理其子进程。
- 读取 stdout / stderr 时保持流式处理并等待 EOF。
- 应用退出时取消未完成任务，停止自有进程并保存偏好。
- UI 状态编排保持在 `@MainActor AppModel`。

修改生命周期代码时，应覆盖启动、取消、异常退出、超时、重复调用和应用退出场景。

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
- `Docs/RELEASING.md`：签名、公证和发布检查。
- `THIRD_PARTY_NOTICES.md`：第三方版本、来源和许可证义务。

产品历史或内部验收对照不应出现在用户文档和应用文案中。
