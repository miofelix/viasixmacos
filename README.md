# ViaSix for macOS

ViaSix 是参考 `ipv6-plan` 业务流程重写的原生 macOS 客户端。它把 CloudflareSpeedTest（CFST）节点优选、Xray 配置切换、代理进程控制、出口 IP 检测和运行日志集中到一个简洁的 SwiftUI 界面中。

项目不会把第三方可执行文件提交到仓库。应用可从上游官方 GitHub Releases 下载固定版本并校验 SHA-256，也可以使用用户指定的本机组件。

## 功能对照

| `ipv6-plan` 能力 | ViaSix macOS 实现 |
| --- | --- |
| IPv6 / IPv4 地址列表测速 | 内置两类地址列表，也支持自定义文件和 CIDR / IP 段 |
| CFST 参数配置 | 覆盖参考 Dashboard 的 17 项参数并持久化 |
| 测速进度与停止 | 实时解析进度、输出和心跳，可安全停止整个自有进程组 |
| 测速结果 | 解析新生成的 CSV，展示 Top 3 与完整七列表格 |
| 节点切换 | 点击结果即可原子更新 Xray 配置；代理运行中会自动重启 |
| Xray 控制 | 启动前校验配置，支持启动、停止、重启、端口就绪和异常退出检测 |
| 出口信息 | 可通过直连或当前本地代理检测出口 IP 与地区 |
| 日志 | 集中显示应用、CFST 和 Xray 的本次会话日志，最多保留 500 条 |
| 托盘操作 | macOS 菜单栏可显示主窗口、控制测速和 Xray，并安全退出 |
| 运行组件 | 支持官方组件下载、固定哈希校验、本地导入和自定义路径 |

相较参考实现，ViaSix 只终止自己启动的子进程，不会按进程名全局结束 Xray；测速前会移除旧 CSV，避免失败后误读历史结果；配置更新采用原子替换。

## 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon（arm64）或 Intel（x86_64）Mac
- 从源码构建需要 Xcode 16.3 或更高版本以及 Swift 6.1
- 使用在线安装组件、测速和出口检测时需要网络连接

## 首次使用

1. 打开 ViaSix，在“设置”中选择“安装官方组件”。应用会下载当前架构对应的 CFST `v2.3.5` 与 Xray-core `v26.3.27`，校验固定 SHA-256 后安装。
2. 在“节点优选”中选择 IPv6、IPv4、自定义文件或 IP 段，按需调整参数并开始测速。
3. 在 Top 3 卡片或结果表中选择节点。ViaSix 会把该地址写入 Xray 模板生成的配置。
4. 回到“概览”启动 Xray。默认 mixed HTTP/SOCKS 入站为 `127.0.0.1:11451`。
5. 在需要代理的应用中手动填写上述地址，或按该应用支持的方式设置代理。ViaSix **不会修改 macOS 系统代理**。

命令行程序可按需使用：

```bash
export HTTP_PROXY=http://127.0.0.1:11451
export HTTPS_PROXY=http://127.0.0.1:11451
export ALL_PROXY=socks5h://127.0.0.1:11451
```

运行组件的查找顺序为：设置中的自定义路径、ViaSix 管理的副本、Homebrew 常用路径、当前进程的 `PATH`。本地导入时可以选择可执行文件、解压后的目录或多个相关文件；ViaSix 会识别 `cfst`、`xray`、`geoip.dat` 和 `geosite.dat`。

## 应用数据

应用包视为只读，所有可变数据都位于：

```text
~/Library/Application Support/ViaSix/
  Data/
    preferences.json   参数、自定义组件路径与当前节点
    ip.txt             默认 IPv4 地址列表
    ipv6.txt           默认 IPv6 地址列表
    template.json      可编辑的 Xray 配置模板
    config.json        当前节点生成的 Xray 配置
    result.csv         最新测速结果；开始新测速前会清除
  Runtime/
    cfst
    xray
    geoip.dat
    geosite.dat
  Logs/                预留的持久化日志目录
```

默认列表和模板只会在文件不存在时复制，应用升级不会覆盖用户修改。界面中的运行日志当前仅保存在内存中，退出应用后清空。

> [!IMPORTANT]
> `template.json` 沿用参考项目的 VLESS 连接资料。公开分发、共享构建产物或投入生产使用前，请确认这些连接资料的授权、安全性和有效性，并按实际部署替换 UUID、主机名及传输参数。

## 本地开发

```bash
make build
make test
swift run ViaSix
```

生成可双击运行的应用并验证 bundle：

```bash
make app
make verify-app
open dist/ViaSix.app
```

`make clean` 只清理仓库中的 SwiftPM 和 `dist` 构建产物，不会删除 `~/Library/Application Support/ViaSix`。

## 签名与分发

`make app` 默认对 `dist/ViaSix.app` 使用 ad-hoc 签名，适合当前 Mac 的开发和冒烟测试。ad-hoc 签名不具备开发者身份，也没有经过 Apple 公证，不应作为面向其他用户的正式发布包。

配置 Developer ID Application 证书后，可让打包脚本启用 Hardened Runtime、时间戳和指定身份签名：

```bash
VIASIX_CODESIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID)" make app
```

正式分发还应使用 `notarytool` 提交公证并装订 ticket，例如：

```bash
ditto -c -k --keepParent dist/ViaSix.app dist/ViaSix.zip
xcrun notarytool submit dist/ViaSix.zip --keychain-profile "notary-profile" --wait
xcrun stapler staple dist/ViaSix.app
spctl --assess --type execute --verbose=4 dist/ViaSix.app
```

ViaSix 需要启动外部网络工具并在 Application Support 中维护它们，因此当前分发模型是 Developer ID + 公证，而不是 Mac App Store 沙盒。应用不需要管理员权限，也不会安装系统扩展或网络扩展。首次运行未公证的本地构建时，macOS Gatekeeper 仍可能要求用户确认。

## 网络与隐私边界

- 组件安装连接 CFST 与 Xray-core 的官方 GitHub Releases。
- CFST 会连接其默认测速地址，或用户在参数中填写的自定义 URL。
- 出口 IP 检测连接 `https://api.myip.la/cn?json`；Xray 运行时会通过本地代理请求。
- ViaSix 仅监听回环地址 `127.0.0.1:11451`，不会主动开放局域网端口。
- ViaSix 不收集遥测；第三方组件和网络服务受各自许可与隐私政策约束。

## 工程结构

```text
Sources/
  ViaSixCore/       模型、解析、配置、下载、进程与持久化
  ViaSixApp/        SwiftUI 界面、菜单栏与应用生命周期
Tests/
  ViaSixCoreTests/  核心逻辑及进程行为测试
Packaging/          App bundle 元数据
Scripts/            构建、打包与 bundle 验证脚本
Docs/               架构说明
```

完整测试会验证参数到 CLI 的映射、CSV 与流式输出解析、偏好兼容、配置原子更新、运行组件校验安装，以及 CFST / Xray 的进程生命周期。打包验证会检查 Info.plist、主程序、内置资源、第三方声明和代码签名。

架构和进程边界见 [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md)，第三方版本与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
