# ViaSix for macOS

ViaSix 是一款以 IPv6 为核心的原生 macOS 网络工具：它测试并选择可用的 IPv6 代理入口，再通过 Mihomo 让本机流量连接该 IPv6 地址。

这里的“走 IPv6”指 Mac 到远程代理入口使用 IPv6。远程代理访问最终网站时，出口仍可能是 IPv4。

> [!IMPORTANT]
> ViaSix 不提供代理账号、订阅、服务器或网络接入服务。你需要准备自己有权使用的 Mihomo YAML 配置。

## 产品边界

ViaSix 只保留一套 IPv6-first 运行模型：

- 规则和全局模式必须使用有效 IPv6 节点及可注入地址的内联代理；
- 直连模式不加载远程代理；
- Provider-only、IPv4 节点、导入规则、代理组选择和旧 Xray 配置迁移不受支持；
- 系统代理和 TUN 虚拟网卡是两个独立开关，可单独或同时启用；
- 日志保留为独立主页面。

## 主要功能

- 测试内置或自定义 IPv6 地址、单个地址和 CIDR；
- 按延迟、丢包率、下载速度和地区比较结果；
- 一键应用 IPv6 节点，运行中自动重新连接；
- 首页切换规则、全局和直连模式；
- 首页独立控制 macOS 系统代理和 TUN 虚拟网卡；
- 首页实时流量统计：上下行速率、流量曲线与 Mihomo 内存占用；
- 导入并编辑 VLESS、VMess、Trojan 和 Shadowsocks 内联代理；
- 检测最终出口 IP，并区分“IPv6 代理入口”和“网站出口”；
- 完整日志界面支持来源/级别筛选、跟随、排序和清空；
- 菜单栏提供启停、重连、IPv6 优选、日志、设置入口，以及运行中的上下行速率；
- 配置只保存在本机，不收集遥测。

ViaSix 使用 XIU2/CloudflareSpeedTest 完成节点测速，使用 MetaCubeX/mihomo 提供代理能力。CloudflareSpeedTest 并非 Cloudflare 官方产品。

## 系统要求

- macOS 14 Sonoma 或更高版本；
- Apple Silicon（arm64）或 Intel（x86_64）Mac；
- 安装组件、测速和出口检测时需要网络连接。

## 快速开始

1. 在“设置 → 运行组件”安装 CloudflareSpeedTest；如需本地代理运行，同时安装 Mihomo。
2. 如需 TUN，在“设置 → 虚拟网卡服务”安装服务和特权 Mihomo。
3. 在“连接配置”导入含内联代理的 Mihomo YAML。
4. 在“IPv6 优选”测试并应用一个 IPv6 节点。
5. 返回首页选择规则、全局或直连，并按需分别开启系统代理和虚拟网卡。
6. 启动连接；出现问题时打开“日志”。

规则模式会只保留主内联代理，把其 `server` 替换为所选 IPv6，并生成私网直连、其余流量走主代理的规则。全局模式同样只使用该 IPv6 主代理。直连模式生成 `MATCH,DIRECT`，不需要节点或代理配置。

## 配置示例

```yaml
proxies:
  - name: My VLESS
    type: vless
    server: origin.example.com
    port: 443
    uuid: 11111111-1111-4111-1111-111111111111
    network: ws
    tls: true
    servername: origin.example.com
    ws-opts:
      path: /proxy
      headers:
        Host: origin.example.com
```

ViaSix 会在规则或全局模式下把 `server` 替换为当前 IPv6，同时保留端口、凭据、传输、TLS、SNI/Host 和路径等连接身份字段。导入的规则、Provider 和代理组不会进入运行配置。

Cloudflare Pages 生成器使用更明确的模板：

```yaml
x-viasix:
  version: 1
  primary-server: selected-ip
```

该扩展只声明节点地址来自 ViaSix 当前选择，不覆盖代理模式、系统代理、TUN、日志或其他本机设置。

## 从源码构建

开发环境需要 Xcode 16.3 / Swift 6.1 或更高版本。

```bash
make check
make app
open dist/ViaSix.app
```

`make app` 生成适合本机开发和验证的 ad-hoc 签名应用。首次安装 TUN 服务时会请求管理员授权；日常启停不需要重复输入密码。

## 数据与隐私

可变数据默认位于：

```text
~/Library/Application Support/ViaSix/
```

- ViaSix 不要求账号，也不收集遥测；
- mixed 代理和 Controller 只绑定回环地址，Controller 使用随机密钥；
- `profile.yaml` 可能包含 UUID、域名和密钥，请勿公开；
- TUN helper 只能启动应用内固定签名的 Mihomo；
- 出口检测会访问设置中配置的检测服务。

## 常见问题

### 为什么选择了 IPv6 节点，出口仍显示 IPv4？

ViaSix 保证的是 Mac 到远程代理入口使用 IPv6。代理服务器到目标网站的地址族由服务器和网站决定。

### 为什么 Provider-only 配置不能启动？

ViaSix 必须明确找到一个可替换 `server` 的内联主代理，才能保证连接入口使用所选 IPv6。远端 Provider 无法提供这一保证。

### 系统代理和 TUN 可以同时开启吗？

可以。两者是首页上的独立开关：系统代理覆盖遵循 macOS 代理设置的应用，TUN 用于接管其他流量。也可以只开启其中一个，或都关闭后仅使用本地 mixed 端口。

### 日志界面还保留吗？

保留。日志是独立主页面，支持筛选、跟随最新记录、排序和清空。

## 文档

- [用户指南](Docs/USER_GUIDE.md)
- [开发说明](Docs/DEVELOPMENT.md)
- [架构说明](Docs/ARCHITECTURE.md)
- [虚拟网卡能力边界](Docs/VIRTUAL_NETWORK.md)
- [地址列表来源](Docs/ADDRESS_SOURCES.md)
- [发布指南](Docs/RELEASING.md)
- [安全政策](SECURITY.md)
- [隐私说明](PRIVACY.md)

## 许可证

ViaSix 基于 [MIT License](LICENSE) 发布。第三方组件继续受各自许可证约束。
