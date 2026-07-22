# ViaSix

ViaSix 是一款以 **IPv6 为核心** 的网络工具：测试并选择可用的 IPv6 代理入口，再通过 Mihomo 让本机流量连接该地址。

这里的“走 IPv6”指设备到远程代理入口使用 IPv6。远程代理访问最终网站时，出口仍可能是 IPv4。

> [!IMPORTANT]
> ViaSix 不提供代理账号、订阅、服务器或网络接入服务。你需要准备自己有权使用的 Mihomo YAML 配置。

## 仓库结构（Monorepo）

本仓库按 **契约中心 + 多端壳** 组织，可同时演进 macOS / Windows / Android：

```text
contracts/          跨端配置 schema 与黄金 fixture
packages/           可选共享库（渐进引入）
apps/
  macos/            原生 macOS 客户端（可构建）
  windows/          Windows 骨架（阶段 1）
  android/          Android 骨架（阶段 2）
server/             Cloudflare Pages 等
docs/               架构与平台说明
```

| 平台 | 状态 | 入口 |
| --- | --- | --- |
| macOS | **可用** | [apps/macos](apps/macos/README.md) |
| Windows | MVP（Tauri） | [apps/windows](apps/windows/README.md) |
| Android | 骨架 | [apps/android](apps/android/README.md) |

布局与路线图：

- [Monorepo 布局](docs/architecture/repo-layout.md)
- [跨平台路线](docs/architecture/roadmap.md)

## macOS 客户端（当前产品）

原生 SwiftUI 应用，支持：

- IPv6 节点测速与优选；
- 规则 / 全局 / 直连，以及独立的系统代理与 TUN 开关；
- 首页实时流量统计与菜单栏速率；
- 导入并编辑内联 Mihomo 代理；
- 固定签名的特权 TUN 服务。

### 系统要求

- macOS 14 Sonoma 或更高版本；
- Apple Silicon（arm64）或 Intel（x86_64）Mac。

### 从源码构建

开发环境需要 Xcode 16.3 / Swift 6.1 或更高版本。

```bash
# 在仓库根目录
make check          # contracts + macOS lint/build/test
make macos-app      # 打包 ad-hoc ViaSix.app
open apps/macos/dist/ViaSix.app
```

也可进入应用目录：

```bash
cd apps/macos
make check
make app
open dist/ViaSix.app
```

`make macos-app` 生成适合本机开发和验证的 ad-hoc 签名应用。首次安装 TUN 服务时会请求管理员授权；日常启停不需要重复输入密码。

### 快速开始（用户）

1. 在“设置 → 运行组件”安装 CloudflareSpeedTest；如需本地代理运行，同时安装 Mihomo。
2. 如需 TUN，在“设置 → 虚拟网卡服务”安装服务和特权 Mihomo。
3. 在“连接配置”导入含内联代理的 Mihomo YAML。
4. 在“IPv6 优选”测试并应用一个 IPv6 节点。
5. 返回首页选择规则、全局或直连，并按需分别开启系统代理和虚拟网卡。
6. 启动连接；出现问题时打开“日志”。

## 产品边界

- 规则和全局模式必须使用有效 IPv6 节点及可注入地址的内联代理；
- 直连模式不加载远程代理；
- Provider-only、IPv4 节点、导入规则、代理组选择和旧 Xray 配置迁移不受支持；
- 系统代理和 TUN 虚拟网卡是两个独立开关（Android 无系统代理）；
- 日志保留为独立主页面。

## 数据与隐私

macOS 可变数据默认位于：

```text
~/Library/Application Support/ViaSix/
```

详见 [PRIVACY.md](PRIVACY.md)。

## 文档

| 文档 | 说明 |
| --- | --- |
| [macOS 用户指南](apps/macos/Docs/USER_GUIDE.md) | 终端用户 |
| [macOS 开发说明](apps/macos/Docs/DEVELOPMENT.md) | 贡献者 |
| [macOS 架构说明](apps/macos/Docs/ARCHITECTURE.md) | 模块与不变量 |
| [虚拟网卡边界](apps/macos/Docs/VIRTUAL_NETWORK.md) | TUN / helper |
| [发布指南](apps/macos/Docs/RELEASING.md) | 维护者 |
| [安全政策](SECURITY.md) | 漏洞报告 |
| [参与贡献](CONTRIBUTING.md) | 协作流程 |

## 许可证

ViaSix 基于 [MIT License](LICENSE) 发布。第三方组件继续受各自许可证约束；见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
