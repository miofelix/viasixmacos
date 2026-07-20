# 第三方声明

ViaSix 使用以下第三方库，并可以下载、执行独立命令行程序。它们继续受各自许可证约束。下列固定版本或源码审计基线的许可证原文会随应用包提供离线副本，可通过下方各组件的语义化链接在 ViaSix 内查看。实际安装的外部组件版本及对应源码以相应 GitHub Release 为准。

## Yams

- 项目：jpsim/Yams
- 固定版本：6.2.2
- 源码：https://github.com/jpsim/Yams/tree/6.2.2
- 固定提交：`a27b21e0c81c5bf42049b897a62aaf387e80f279`
- 许可证：MIT License
- 上游许可证：https://github.com/jpsim/Yams/blob/6.2.2/LICENSE
- 离线原文：[Yams · MIT](ThirdPartyLicenses/Yams-MIT.txt)

Yams 作为 Swift Package 固定到上述版本，用于读取和生成 Mihomo 原生 YAML 配置。

## CloudflareSpeedTest

- 项目：XIU2/CloudflareSpeedTest
- 审计基线版本：v2.3.5
- 源码：https://github.com/XIU2/CloudflareSpeedTest/tree/v2.3.5
- 固定提交：`65b43aa58c5f9c7ab8ab83d2d27e35fc00d9cec4`
- 许可证：GNU General Public License v3.0
- 上游许可证：https://github.com/XIU2/CloudflareSpeedTest/blob/v2.3.5/LICENSE
- 离线原文：[CloudflareSpeedTest · GPL-3.0](ThirdPartyLicenses/CloudflareSpeedTest-GPL-3.0.txt)

CloudflareSpeedTest 是 XIU2 维护的独立第三方项目，并非 Cloudflare 官方产品。ViaSix 下载其未修改的 macOS 正式发布压缩包。若发布者把 ViaSix 与该二进制一同分发，发布者有责任满足 GPLv3 的源码和声明义务。

## Mihomo

- 项目：MetaCubeX/mihomo
- 固定版本：v1.19.29
- 源码：https://github.com/MetaCubeX/mihomo/tree/v1.19.29
- 固定提交：`e26714a181ac0e2fa803453c0a8e9a9ce94e31cb`
- 许可证：GNU General Public License v3.0
- 上游许可证：https://github.com/MetaCubeX/mihomo/blob/v1.19.29/LICENSE
- 离线原文：[Mihomo · GPL-3.0](ThirdPartyLicenses/mihomo-GPL-3.0.txt)

ViaSix 按 CPU 架构下载 Mihomo v1.19.29 的未修改 macOS 正式发布包，校验压缩包与可执行文件后安装到当前用户的应用数据目录，并以当前用户权限运行本地代理。若发布者把 ViaSix 与 Mihomo 二进制一同分发，或以其他方式构成 GPLv3 所涵盖的分发，发布者有责任满足对应的源码和声明义务。

## 第三方网络服务

未设置自定义测速 URL 时，CloudflareSpeedTest 可能使用其上游默认测速地址。自动出口 IP 检测默认使用 `https://api.myip.la/cn?json`；强制 IPv4 / IPv6 检测分别使用 `https://api-ipv4.ip.sb/ip` 与 `https://api-ipv6.ip.sb/ip`。检测成功后，ViaSix 还会向 `https://ipwho.is/<IP>?lang=zh-CN` 查询中文地理和网络信息。这些服务受各自可用性、日志和隐私政策约束。
