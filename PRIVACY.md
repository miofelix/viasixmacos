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
- 用户导入的 `template.json` 及生成的 `config.json`
- ViaSix 管理的第三方运行组件

代理配置可能包含 UUID、域名、端口、密钥或其他敏感信息。ViaSix 将应用数据目录限制为当前用户访问，但磁盘备份、恶意软件、拥有同等用户权限的进程或用户主动分享仍可能暴露这些文件。

界面中的运行记录当前只保存在内存中，退出应用后清空。

## 网络连接

根据用户执行的操作，ViaSix 可能连接：

- CloudflareSpeedTest 和 Xray-core 的 GitHub Releases，用于下载固定版本组件
- CloudflareSpeedTest 的上游默认测速地址，或用户填写的自定义测速 URL
- 默认使用 `https://api.myip.la/cn?json` 检测出口 IP；用户也可以在设置中指定其他 HTTP / HTTPS 服务
- 用户 Xray 配置指定的服务器、DNS 和目标站点

ViaSix 无法控制这些第三方服务的日志、隐私政策、可用性或司法管辖范围。`XIU2/CloudflareSpeedTest` 是独立第三方项目，并非 Cloudflare 官方产品。

## 遥测边界

ViaSix 本身不会把设置、测速结果或代理配置发送给 ViaSix 维护者。第三方运行组件及用户访问的网络服务会产生其正常工作所需的网络流量，这不属于 ViaSix 产品遥测。

## 保留、备份与删除

- 完全退出应用后，可备份整个 `ViaSix` Application Support 文件夹。
- 删除 `.app` 不会自动删除用户数据。
- 要彻底清除本地数据，请先退出 ViaSix，再删除 `~/Library/Application Support/ViaSix/`。
- 若使用 Time Machine、云盘或其他备份工具，还需按相应产品规则清理历史副本。

更详细的文件说明见[用户指南](Docs/USER_GUIDE.md)。网络端点或数据行为发生变化时，应同步更新本文。
