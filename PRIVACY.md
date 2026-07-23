# ViaSix 隐私说明

ViaSix 是 **全平台** 本地运行的网络客户端（macOS / Windows / Android；Linux 桌面规划中）。不要求 ViaSix 账号，也不包含产品遥测或分析 SDK。

## 本机保存的数据

默认数据目录因平台而异：

| 平台 | 默认位置（概要） |
| --- | --- |
| macOS | `~/Library/Application Support/ViaSix/` |
| Windows | Tauri `app_data_dir`（identifier `dev.viasix.windows`，通常在 `%APPDATA%\dev.viasix.windows`） |
| Android | 应用私有存储（如 `filesDir` 下的运行目录与偏好） |
| Linux | 规划中；预期遵循 XDG / Tauri `app_data_dir` |

其中可能包含：

- 测速参数、自定义组件路径和当前节点
- IPv4 / IPv6 地址列表与最近一次测速结果（若该端支持测速）
- Mihomo 服务器配置、本机代理设置、生成的运行配置、Provider 缓存与系统代理恢复快照（桌面端）
- ViaSix 管理的第三方运行组件
- 会话偏好（代理模式、分区记忆、本地端口等）
- Android 分应用路由所选择的应用包名；应用选择器仅在本机查询具有启动器入口的应用，不上传应用列表

代理配置可能包含 UUID、域名、端口、密钥或其他敏感信息。ViaSix 将应用数据目录限制为当前用户（或应用沙箱）访问，但磁盘备份、恶意软件、拥有同等用户权限的进程或用户主动分享仍可能暴露这些文件。

界面中的运行记录（活动日志）在多数端当前以会话内存为主；是否落盘以实现为准，退出后是否保留见各端说明。

## 网络连接

根据用户执行的操作，ViaSix 可能连接：

- CloudflareSpeedTest 和 Mihomo 的固定 GitHub Releases 资产，用于下载当前架构的清单版本组件（各端拉取脚本/路径不同）
- CloudflareSpeedTest 的上游默认测速地址，或用户填写的自定义测速 URL（支持测速的端）
- 出口 IP / 地理信息检测所用的 HTTP(S) 服务（端点与是否经本地代理因端与用户设置而异）
- 用户 Mihomo 配置指定的服务器、Proxy Provider、Rule Provider、DNS 和目标站点

ViaSix 无法控制这些第三方服务的日志、隐私政策、可用性或司法管辖范围。`XIU2/CloudflareSpeedTest` 是独立第三方项目，并非 Cloudflare 官方产品。

## 遥测边界

ViaSix 本身不会把设置、测速结果或代理配置发送给 ViaSix 维护者。第三方运行组件及用户访问的网络服务会产生其正常工作所需的网络流量，这不属于 ViaSix 产品遥测。

## 特权与网络接入

在支持的平台上，ViaSix 可能：

- 以当前用户身份启动 Mihomo；
- 修改系统代理设置（macOS / Windows；Android 不适用）；
- 通过平台特权路径使用虚拟网卡或 VPN（macOS：XPC helper + utun；Windows：进程内 TUN + Wintun；Android：`VpnService`；Linux：规划中）。

特权路径会触及路由、DNS 或隧道接口。具体边界见各端虚拟网卡/VPN 文档（如 macOS `apps/macos/Docs/VIRTUAL_NETWORK.md`、Windows `apps/windows/Docs/VIRTUAL_NETWORK.md`）。

## 保留、备份与删除

- 桌面端完全退出应用后，可按需备份对应平台的数据目录；Android 应用声明禁用系统云备份和设备迁移，并显式排除全部私有数据域。
- 卸载或删除应用包/APK **不会**保证自动删除用户数据。
- 要彻底清除本地数据，请先退出 ViaSix，再删除上表中的数据目录（Android 可在系统设置中清除应用数据）。
- 若使用系统备份、云盘或其他备份工具，还需按相应产品规则清理历史副本。

更详细的 macOS 文件说明见应用内用户指南（仓库路径 `apps/macos/Docs/USER_GUIDE.md`；应用包内为 `Docs/USER_GUIDE.md`）。网络端点或数据行为发生变化时，应同步更新本文。
