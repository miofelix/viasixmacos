# ViaSix for macOS

ViaSix 是一款原生 macOS 网络工具，用于测试 IPv4 / IPv6 边缘节点、比较延迟与下载速度，并把选中的节点应用到你自己的 Xray 连接配置。节点测速、本地代理、出口 IP 检测和活动日志都集中在一个简洁的界面中，也可以通过菜单栏快速控制。

> [!IMPORTANT]
> ViaSix 不提供代理账号、订阅、服务器或网络接入服务。使用本地代理前，你需要准备一份自己有权使用的兼容 Xray JSON 配置。

> [!NOTE]
> 当前仓库提供源码构建和本地 ad-hoc 打包流程。普通用户应只安装维护者明确发布、签名并公证的产物；在正式下载地址公布前，请按下文从源码构建。

## 主要功能

- 使用内置 IPv4 / IPv6 地址列表进行节点测速
- 支持自定义地址文件、单个 IP 和 CIDR 网段
- 按延迟、丢包率、下载速度和地区筛选候选节点
- 展示前三名节点与完整测速结果
- 一键应用节点；本地代理运行时可自动重新连接
- 启动、停止和重启本地 HTTP / SOCKS 代理
- 检测直连或代理状态下的出口 IP
- 展示出口 IP 的国家、地区、城市、网络运营商、ASN 与时区
- 通过菜单栏控制常用操作
- 在本机保存设置、地址列表和代理配置，不收集遥测

ViaSix 使用第三方项目 XIU2/CloudflareSpeedTest 完成节点测速，使用 Xray-core 提供本地代理能力。CloudflareSpeedTest 并非 Cloudflare 官方产品。组件在首次使用时按需从各自上游 Release 下载，也可以从本机导入。

## 系统要求

- macOS 14 Sonoma 或更高版本
- Apple Silicon（arm64）或 Intel（x86_64）Mac
- 安装组件、节点测速和出口检测时需要网络连接

## 安装

### 使用发布包

1. 从维护者公布的正式发布页获取适合当前 Mac 的 `ViaSix.app`。
2. 将应用拖入“应用程序”文件夹。
3. 打开 ViaSix。

如果 macOS 提示无法验证本地构建，请先确认应用来源可信，再在 Finder 中按住 Control 点击应用并选择“打开”。不要为了运行 ViaSix 关闭 Gatekeeper 或系统完整性保护。

### 从源码构建

开发环境需要 Xcode 16.3 / Swift 6.1 或更高版本；Xcode 16.3 本身要求 macOS 15.2 或更高版本。

```bash
make check
make app
open dist/ViaSix.app
```

本地 `make app` 生成 ad-hoc 签名包，只适合开发和冒烟测试。完整说明见[开发文档](Docs/DEVELOPMENT.md)。

## 快速开始

1. 打开“设置”，安装测速与代理组件。
2. 进入“节点测速”，选择 IPv6、IPv4、自定义文件或 IP / CIDR。
3. 点击“开始测速”，查看候选节点；单独测速不需要 Xray 配置。
4. 如果需要本地代理，在“代理配置”中导入你自己的兼容 Xray JSON 文件并选择节点。
5. 回到“连接”打开本地代理开关。
6. 在需要使用代理的应用中填写“设置”里显示的本地端点。

ViaSix 会从 Xray 配置中的回环 `mixed` 入站读取本地端点，同一个端口可作为 HTTP 或 SOCKS5 代理使用。ViaSix 不会自动修改 macOS 系统代理。

更完整的配置格式、参数说明、备份方法和排错步骤见 [用户指南](Docs/USER_GUIDE.md)。

## 数据与隐私

ViaSix 的可变数据默认保存在：

```text
~/Library/Application Support/ViaSix/
```

- 设置、测速地址列表和代理配置只保存在本机。
- ViaSix 不收集遥测，也不要求创建 ViaSix 账号。
- 安装组件时会连接 CloudflareSpeedTest 与 Xray-core 各自上游项目的发布地址。
- 节点测速会访问测速组件的默认地址，或你填写的自定义测速 URL。
- 出口 IP 检测可选择自动、IPv4 或 IPv6；自动模式默认使用 `https://api.myip.la/cn?json`，也可在设置中改为其他 HTTP / HTTPS 服务，强制地址族时使用 IP.SB 的对应专用端点。检测成功后，ViaSix 会通过 `https://ipwho.is/<IP>?lang=zh-CN` 补充中文国家、地区、城市、邮编、网络运营商、ASN 和时区；地理信息服务不可用时仍会显示已检测到的 IP。
- 本地代理只允许监听 Xray 配置声明的回环地址和端口，不会主动向局域网开放端口。

第三方组件及网络服务受各自许可证、隐私政策和可用性约束。
完整的数据、网络连接、保留和删除说明见[隐私说明](PRIVACY.md)。

## 安全说明

- 代理配置可能包含 UUID、域名、密钥或其他敏感资料，请勿上传、公开或发送给不受信任的人。
- ViaSix 不会把第三方可执行文件直接存放在源码仓库中；在线安装会从组件上游发布页下载并校验文件完整性。
- ViaSix 只管理自己启动的测速和代理进程，不会按进程名结束其他应用。
- 关闭主窗口不会退出 ViaSix；应用会继续驻留菜单栏。需要停止所有自有进程时，请从菜单栏选择“退出 ViaSix”。
- ViaSix 不会安装系统扩展或网络扩展，也不需要管理员权限。

## 常见问题

### ViaSix 是否自带代理服务？

不自带。ViaSix 负责节点测速和本地代理进程管理，但不提供服务器、账号或订阅。你必须使用自己有权访问的 Xray 配置。

### 为什么首次启动本地代理时提示连接尚未配置？

应用内置的是不含真实账号的安全示例模板。请在“设置”中导入自己的 Xray JSON，或打开代理配置并填写自己的连接参数。

### ViaSix 会修改系统代理吗？

不会。请在浏览器、下载工具、终端或其他目标应用中单独设置“设置”里显示的本地端点。

### 关闭窗口后为什么菜单栏仍有 ViaSix？

这是正常行为。ViaSix 可以在菜单栏继续测速或维持本地代理。选择菜单栏中的“退出 ViaSix”才会完整退出。

### 测速结果是否代表实际代理速度？

不一定。测速结果反映候选边缘 IP 在当前网络中的表现；最终体验还会受到你的代理服务器、传输配置、网络拥塞和目标站点影响。

### 如何备份或迁移设置？

完全退出 ViaSix 后，备份 `~/Library/Application Support/ViaSix/`。详细的文件用途和恢复步骤见 [用户指南](Docs/USER_GUIDE.md)。

## 文档

- [用户指南](Docs/USER_GUIDE.md)：配置、测速、代理使用、备份与排错
- [开发说明](Docs/DEVELOPMENT.md)：构建、测试、目录结构与开发约定
- [架构说明](Docs/ARCHITECTURE.md)：模块、数据和进程边界
- [发布指南](Docs/RELEASING.md)：签名、公证与发布检查
- [地址列表来源](Docs/ADDRESS_SOURCES.md)：内置 IPv4 / IPv6 快照与更新流程
- [参与贡献](CONTRIBUTING.md)：协作流程、代码规范与验证要求
- [变更日志](CHANGELOG.md)：未发布和已发布版本的重要变化
- [安全政策](SECURITY.md)：私密漏洞报告和供应链约定
- [隐私说明](PRIVACY.md)：本机数据、网络端点与删除方式
- [第三方声明](THIRD_PARTY_NOTICES.md)：组件版本与许可证
- [项目许可证](LICENSE)：ViaSix 自身的授权条款

## 许可证

ViaSix 基于 [MIT License](LICENSE) 发布，版权归 ViaSix contributors 所有。第三方组件继续受各自许可证约束，详见[第三方声明](THIRD_PARTY_NOTICES.md)。
