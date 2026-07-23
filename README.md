# ViaSix

ViaSix 是一款 **全平台**、以 **IPv6 为核心** 的网络客户端：测试并选择可用的 IPv6 代理入口，再通过 Mihomo 让本机流量连接该地址。

| 维度 | 说明 |
| --- | --- |
| **定位** | 本地客户端（非代理账号/订阅服务） |
| **目标平台** | macOS · Windows · Android · **Linux（规划中）** |
| **共享核心** | 跨端配置契约（`contracts/`）+ 投影语义 |
| **平台差异** | UI 壳与特权网络接入（系统代理 / TUN / VPN）按 OS 原生实现 |

这里的“走 IPv6”指设备到远程代理入口使用 IPv6。远程代理访问最终网站时，出口仍可能是 IPv4。

> [!IMPORTANT]
> ViaSix 不提供代理账号、订阅、服务器或网络接入服务。你需要准备自己有权使用的 Mihomo YAML 配置。

## 平台状态

| 平台 | 状态 | 技术栈（摘要） | 入口 |
| --- | --- | --- | --- |
| **macOS** | 可用 | SwiftUI + SwiftPM + XPC TUN helper | [apps/macos](apps/macos/README.md) |
| **Windows** | 可用（MVP 对齐） | Tauri 2 + Rust；Mihomo TUN + Wintun | [apps/windows](apps/windows/README.md) |
| **Android** | 生产可用 | Kotlin + Compose + VpnService（TCP/UDP IPv4/IPv6） | [apps/android](apps/android/README.md) |
| **Linux** | **规划中 / 未开发** | 桌面 GUI：Tauri（复用 Windows 栈） | [docs/platforms/linux.md](docs/platforms/linux.md) |

能力矩阵与「完成」边界见 [docs/architecture/COMPLETION.md](docs/architecture/COMPLETION.md)。推进顺序见 [跨平台路线](docs/architecture/roadmap.md)。

## 仓库结构（Monorepo）

本仓库按 **契约中心 + 多端壳** 组织：共享配置与行为约定，各端独立实现 UI 与特权网络接入。

```text
contracts/          跨端配置 schema 与黄金 fixture（单一事实来源）
packages/           共享库（如 viasix-mihomo-config）
apps/
  macos/            原生 macOS 客户端
  windows/          Windows 客户端（Tauri）
  android/          Android 客户端
  # linux/          规划：桌面 GUI（Tauri，复用 Windows 栈）
server/             Cloudflare Pages 等与客户端无关的服务
docs/               架构与平台说明
toolchains/         跨端工具脚本（渐进迁入）
```

布局细节：[Monorepo 布局](docs/architecture/repo-layout.md)。

各 `apps/*` **不得**相互 import；跨端行为只通过 `contracts/`（及 `packages/`）对齐。

## 产品能力（跨端共识）

各端在 UI 与系统 API 上不同，但用户能力对齐同一产品语义：

- IPv6 节点测速 / 校验与优选（平台实现深度不同）；
- 规则 / 全局 / 直连等代理路由模式；
- 导入并编辑内联 Mihomo 代理配置，按契约投影为运行配置；
- 网络接入：系统代理（桌面端）和/或虚拟网卡 / VPN（按平台）；
- 连接状态、流量与活动日志（展示粒度因端而异）。

### 产品边界

- 规则和全局模式必须使用有效 IPv6 节点及可注入地址的内联代理；
- 直连模式不加载远程代理；
- Provider-only、IPv4 节点、导入规则、代理组选择和旧 Xray 配置迁移不受支持；
- 系统代理与 TUN/VPN 在支持的平台上为独立开关（Android 无系统代理）；
- 日志保留为独立主分区。

## 快速开始

### 开发者（仓库根目录）

```bash
make contracts-check    # schema + fixture 结构
make projection-test    # 各端投影契约
make check              # contracts + 各端测试汇总
```

分端命令示例：

```bash
make macos-app          # 打包 ad-hoc ViaSix.app
make windows-test       # Windows 投影 / cargo test
make android-test       # Android :core 单测
make android-assemble   # 需 Android SDK
```

各端环境要求与完整流程见对应 `apps/*/README.md` 与 [CONTRIBUTING.md](CONTRIBUTING.md)。

### 终端用户（按平台）

| 平台 | 用户文档 |
| --- | --- |
| macOS | [用户指南](apps/macos/Docs/USER_GUIDE.md) · 简要步骤见下 |
| Windows | [apps/windows/README.md](apps/windows/README.md) · [发布说明](apps/windows/Docs/RELEASING.md) |
| Android | [apps/android/README.md](apps/android/README.md) · [发布说明](apps/android/Docs/RELEASING.md) |
| Linux | 尚未提供安装包；见 [规划说明](docs/platforms/linux.md) |

**macOS 简要步骤：**

1. 在「设置 → 运行组件」安装 CloudflareSpeedTest；如需本地代理，同时安装 Mihomo。
2. 如需 TUN，在「设置 → 虚拟网卡服务」安装服务和特权 Mihomo。
3. 在「连接配置」导入含内联代理的 Mihomo YAML。
4. 在「IPv6 优选」测试并应用一个 IPv6 节点。
5. 返回首页选择规则、全局或直连，并按需分别开启系统代理和虚拟网卡。
6. 启动连接；出现问题时打开「日志」。

## 数据与隐私

ViaSix 在**本机**保存配置与运行数据，不要求 ViaSix 账号，也不包含产品遥测 SDK。各端默认数据目录不同，详见 [PRIVACY.md](PRIVACY.md)。

## 文档索引

| 文档 | 说明 |
| --- | --- |
| [Monorepo 布局](docs/architecture/repo-layout.md) | 目录与依赖方向 |
| [跨平台路线](docs/architecture/roadmap.md) | 阶段与 Linux 规划 |
| [完成范围说明](docs/architecture/COMPLETION.md) | 能力矩阵与范围外项 |
| [macOS](docs/platforms/macos.md) / [Windows](docs/platforms/windows.md) / [Android](docs/platforms/android.md) / [Linux](docs/platforms/linux.md) | 平台说明 |
| [macOS 用户指南](apps/macos/Docs/USER_GUIDE.md) | 终端用户（macOS） |
| [macOS 开发说明](apps/macos/Docs/DEVELOPMENT.md) | 贡献者（macOS） |
| [macOS 发布说明](apps/macos/Docs/RELEASING.md) | 维护者（macOS） |
| [Android 发布说明](apps/android/Docs/RELEASING.md) | 维护者（Android） |
| [签名材料](signing/README.md) | 本地密钥库与证书说明 |
| [安全政策](SECURITY.md) | 漏洞报告 |
| [参与贡献](CONTRIBUTING.md) | 协作流程 |

## 许可证

ViaSix 基于 [MIT License](LICENSE) 发布。第三方组件继续受各自许可证约束；见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
