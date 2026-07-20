# 第三方声明

ViaSix 可以下载并执行以下独立命令行程序。第三方二进制不存放在本源码仓库中，并继续受各自许可证约束。自动安装会选择上游最新正式版本；下列版本是源码审计基线，其许可证原文保存在 [`ThirdPartyLicenses/`](ThirdPartyLicenses/) 中，并随应用包提供离线副本。实际安装版本及对应源码以相应 GitHub Release 为准。

## CloudflareSpeedTest

- 项目：XIU2/CloudflareSpeedTest
- 审计基线版本：v2.3.5
- 源码：https://github.com/XIU2/CloudflareSpeedTest/tree/v2.3.5
- 固定提交：`65b43aa58c5f9c7ab8ab83d2d27e35fc00d9cec4`
- 许可证：GNU General Public License v3.0
- 上游许可证：https://github.com/XIU2/CloudflareSpeedTest/blob/v2.3.5/LICENSE
- 离线原文：[CloudflareSpeedTest-GPL-3.0.txt](ThirdPartyLicenses/CloudflareSpeedTest-GPL-3.0.txt)

CloudflareSpeedTest 是 XIU2 维护的独立第三方项目，并非 Cloudflare 官方产品。ViaSix 下载其未修改的 macOS 正式发布压缩包。若发布者把 ViaSix 与该二进制一同分发，发布者有责任满足 GPLv3 的源码和声明义务。

## Xray-core

- 项目：XTLS/Xray-core
- 审计基线版本：v26.3.27
- 源码：https://github.com/XTLS/Xray-core/tree/v26.3.27
- 固定提交：`d2758a023cd7f4174a5a5fa4ff66e487d4342ba0`
- 许可证：Mozilla Public License 2.0
- 上游许可证：https://github.com/XTLS/Xray-core/blob/v26.3.27/LICENSE
- 离线原文：[Xray-core-MPL-2.0.txt](ThirdPartyLicenses/Xray-core-MPL-2.0.txt)

ViaSix 下载其未修改的 macOS 正式发布压缩包。`geoip.dat`、`geosite.dat` 等数据文件随 Xray 发布包提供；发布前仍应核对这些数据文件的具体来源和许可证义务。

## 第三方网络服务

未设置自定义测速 URL 时，CloudflareSpeedTest 可能使用其上游默认测速地址。自动出口 IP 检测默认使用 `https://api.myip.la/cn?json`；强制 IPv4 / IPv6 检测分别使用 `https://api-ipv4.ip.sb/ip` 与 `https://api-ipv6.ip.sb/ip`。检测成功后，ViaSix 还会向 `https://ipwho.is/<IP>?lang=zh-CN` 查询中文地理和网络信息。这些服务受各自可用性、日志和隐私政策约束。
