# ViaSix 隐私说明

ViaSix 是本地运行的 macOS 工具，不要求 ViaSix 账号，也不包含产品遥测或分析 SDK。

## 本机保存的数据

默认目录为：

```text
~/Library/Application Support/ViaSix/
```

其中可能包含：

- 测速参数、自定义组件路径和当前节点
- IPv4 / IPv6 地址列表与最近一次测速结果
- Mihomo 服务器配置 `profile.yaml`、本机代理设置 `local-proxy.json`、生成的 `Mihomo/config.yaml`、Provider 缓存与系统代理恢复快照
- ViaSix 管理的第三方运行组件

代理配置可能包含 UUID、域名、端口、密钥或其他敏感信息。ViaSix 将应用数据目录限制为当前用户访问，但磁盘备份、恶意软件、拥有同等用户权限的进程或用户主动分享仍可能暴露这些文件。

界面中的运行记录当前只保存在内存中，退出应用后清空。

## 网络连接

根据用户执行的操作，ViaSix 可能连接：

- CloudflareSpeedTest 和 Mihomo 的固定 GitHub Releases 资产，用于下载当前架构的清单版本组件
- CloudflareSpeedTest 的上游默认测速地址，或用户填写的自定义测速 URL
- 自动模式默认使用 `https://api.myip.la/cn?json` 检测出口 IP，用户也可以指定其他 HTTP / HTTPS 服务；强制 IPv4 / IPv6 时分别使用 `https://api-ipv4.ip.sb/ip` 与 `https://api-ipv6.ip.sb/ip`。每次主检测成功后，ViaSix 还会把检测到的 IP 放入 `https://ipwho.is/<IP>?lang=zh-CN` 请求，以获取中文国家、地区、城市、邮编、网络运营商、ASN 和时区；该请求沿用当前的直连或本地代理路径。地理信息请求失败不会影响 IP 结果。
- 用户 Mihomo 配置指定的服务器、Proxy Provider、Rule Provider、DNS 和目标站点

ViaSix 无法控制这些第三方服务的日志、隐私政策、可用性或司法管辖范围。`XIU2/CloudflareSpeedTest` 是独立第三方项目，并非 Cloudflare 官方产品。

## 遥测边界

ViaSix 本身不会把设置、测速结果或代理配置发送给 ViaSix 维护者。第三方运行组件及用户访问的网络服务会产生其正常工作所需的网络流量，这不属于 ViaSix 产品遥测。

当前版本的 Mihomo 以登录用户身份运行。虚拟网卡模式不可启用，ViaSix 不会创建 TUN、修改默认路由或接管系统 DNS；若未来开放该能力，本文必须在发布前补充相应的特权服务和 DNS/路由数据边界。

## 保留、备份与删除

- 完全退出应用后，可备份整个 `ViaSix` Application Support 文件夹。
- 删除 `.app` 不会自动删除用户数据。
- 要彻底清除本地数据，请先退出 ViaSix，再删除 `~/Library/Application Support/ViaSix/`。
- 若使用 Time Machine、云盘或其他备份工具，还需按相应产品规则清理历史副本。

更详细的文件说明见[用户指南](Docs/USER_GUIDE.md)。网络端点或数据行为发生变化时，应同步更新本文。
