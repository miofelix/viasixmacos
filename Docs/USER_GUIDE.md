# ViaSix 用户指南

本指南面向使用 ViaSix 的 macOS 用户，介绍首次配置、节点测速、本地代理、数据备份和常见问题。

> [!IMPORTANT]
> ViaSix 不提供代理账号、订阅、服务器或网络接入服务。使用“规则”或“全局”模式时，你需要自行准备有权使用的兼容配置；“直连”模式不需要服务器配置。ViaSix 不能判断第三方代理服务是否合法、可信或可用。

## 目录

- [1. 认识 ViaSix](#1-认识-viasix)
- [2. 首次配置](#2-首次配置)
- [3. 运行节点测速](#3-运行节点测速)
- [4. 使用本地代理](#4-使用本地代理)
- [5. 自定义组件路径](#5-自定义组件路径)
- [6. 应用数据、备份与恢复](#6-应用数据备份与恢复)
- [7. 排查问题](#7-排查问题)
- [8. 安全建议](#8-安全建议)

## 1. 认识 ViaSix

ViaSix 包含两个相互配合的功能：

- **节点测速**：使用 CloudflareSpeedTest 测试 IPv4 / IPv6 候选地址的延迟、丢包和下载速度。
- **本地代理**：运行 Mihomo，在仅限本机访问的回环端点提供 HTTP / SOCKS5 mixed 代理，并按“规则”“全局”或“直连”模式处理进入该端点的连接。

测速结果可以作为第一个内联代理节点的服务器地址，但端口、认证信息、传输方式、TLS、Host 和路径仍来自你自己的配置。Provider-only 配置由 Provider 管理节点，不会被测速结果改写。“直连”模式不读取任何远端代理或 Provider，但仍需要 Mihomo 提供本地端点。

ViaSix 提供三种网络接入方式：

- **本地代理**：只处理手动指向本地端点的应用。
- **系统代理**：把当前启用的 macOS 网络服务指向本地端点，只影响遵循系统代理的应用。
- **虚拟网卡**：界面中可见但目前不可启用。当前版本不会创建 TUN、修改默认路由或接管系统 DNS。

## 2. 首次配置

### 2.1 安装运行组件

1. 打开 ViaSix。
2. 进入“设置 → 运行组件”。
3. 选择“安装组件”。
4. 等待 CloudflareSpeedTest 和 Mihomo 均显示为已就绪。

ViaSix 根据当前 Mac 的处理器架构下载固定版本的正式资产。下载前后的压缩包 SHA-256、解压后文件大小和 SHA-256 都会与内置清单核对；任何一步不匹配都会停止安装并保留原来可用的组件。该操作需要访问 GitHub Releases。

CloudflareSpeedTest 是 XIU2 维护的独立第三方项目，并非 Cloudflare 官方产品。代理内核来自 MetaCubeX/mihomo。版本、来源和许可证见[第三方声明](../THIRD_PARTY_NOTICES.md)。

如果你已经在本机准备了组件，也可以使用“导入组件”。ViaSix 会识别：

- `cfst`
- `mihomo`

自定义文件必须与当前 Mac 架构兼容并具有执行权限。只使用节点测速时不需要 Mihomo；启动任意代理模式都需要 Mihomo。

### 2.2 选择代理模式并配置服务器

1. 在“首页”或“设置 → 本机代理”中选择“规则”“全局”或“直连”。
2. 使用“规则”或“全局”时，打开“设置 → 服务器连接”。
3. 选择一种输入方式：
   - “手动配置”：填写协议、服务器地址、端口、认证信息、传输和 TLS / REALITY 参数。
   - “分享链接”：读取 `vless://`、`vmess://`、`trojan://` 或 `ss://` 链接，再核对表单内容。
   - “高级”：编辑或导入 Mihomo YAML，用于多节点、Proxy Provider、代理组和规则。
4. 在“设置 → 本机代理”中修改回环监听地址、端口、UDP、协议嗅探、私有地址直连、日志级别和网络接入方式。
5. 保存后启动代理。“直连”模式可以跳过服务器配置。

ViaSix 会校验结构和必填项，但不会验证账号是否有效，也不会替你购买或生成连接资料。更换服务器配置或本机监听参数前，建议先停止本地代理。

可视化表单只适合一个受支持的内联节点。多节点、Provider、代理组或自定义规则不会被表单压缩成单节点；这类配置请继续使用高级 YAML 编辑器。

### 2.3 Mihomo YAML 要求

高级编辑器接受 UTF-8 Mihomo YAML。可以直接导入：

- 单个节点映射；
- 含 `proxies` 的多节点配置；
- 含 `proxy-providers` 的 Provider 配置；
- `proxy-groups`、`rules`、`rule-providers` 和 `sub-rules`。

本机 `mixed-port`、`bind-address`、`allow-lan`、日志、嗅探、UDP、代理模式和 TUN 不能由服务器配置覆盖，它们由“设置 → 本机代理”统一管理。ViaSix 固定 `allow-lan: false`，监听地址只允许 `127.0.0.0/8`、`::1` 或 `localhost`。

一个最小内联节点示例：

```yaml
proxies:
  - name: My VLESS
    type: vless
    server: origin.example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    network: ws
    tls: true
    servername: origin.example.com
    ws-opts:
      path: /proxy
      headers:
        Host: origin.example.com
```

一个 HTTP Proxy Provider 示例：

```yaml
proxy-providers:
  subscription:
    type: http
    url: https://subscription.example.com/profile.yaml
    interval: 3600

proxy-groups:
  - name: Main
    type: select
    use:
      - subscription

rules:
  - MATCH,Main
```

ViaSix 会把 HTTP Provider 的缓存路径限制在自己的 `Data/Mihomo/providers/` 或 `rules/` 目录。`inline` Provider 可以直接保存在 YAML 中；任意本地文件 Provider 路径和其他未支持 Provider 类型会被拒绝。

节点应用规则：

- 已选择测速节点且配置包含内联代理时，只替换第一个具有 `server` 的内联节点地址。
- 没有选择测速节点时，保留 YAML 中原来的服务器地址。
- Provider-only 配置不要求选择测速节点，也不会改写订阅内容。
- 端口、凭据、TLS / REALITY 标识、其余节点、代理组和规则保持不变。
- “直连”运行配置不会包含代理、Provider、代理组或远端规则。

高级编辑器能识别部分旧 Xray JSON，并在你明确选择迁移后转换为 Mihomo YAML。只支持语义明确的单节点结构；无法无损转换的配置会给出错误，不会直接交给 Mihomo 运行。迁移后请逐项核对协议、传输和 TLS / REALITY 参数。

> [!CAUTION]
> `profile.yaml` 通常包含敏感连接资料，并以普通文件形式保存在本机。不要把配置、截图或备份提交到公开仓库。

## 3. 运行节点测速

### 3.1 选择地址来源

进入“节点”，选择以下来源之一：

- **IPv6**：使用 ViaSix 内置的 IPv6 地址列表。
- **IPv4**：使用 ViaSix 内置的 IPv4 地址列表。
- **自定义文件**：选择纯文本或 CSV 地址列表。
- **自定义 CIDR**：直接输入单个 IP、CIDR 或使用英文逗号分隔的组合。

自定义地址示例：

```text
2606:4700::/32, 104.16.0.0/12
```

只测试你有权访问且符合用途的地址范围。较大的 CIDR、过高的线程数或“测试全部 IPv4”会明显增加耗时和网络负载。

### 3.2 选择测速方式

- **TCPing**：速度快、资源占用较低，适合先筛选可达性和延迟。
- **HTTPing**：可获得 HTTP 状态和地区信息，适合需要地区筛选的场景。

多数用户可以先使用默认参数。需要更精确控制时，可调整：

- 测速端口
- 延迟上下限
- 丢包率上限
- 下载速度下限
- 延迟测速线程数
- 单 IP Ping 次数
- 下载测速节点数量与时长
- 自定义测速 URL
- 地区代码过滤

参数会自动保存在本机。选择“恢复默认设置…”可恢复默认测速参数。

### 3.3 开始、停止和查看结果

1. 确认地址来源和参数。
2. 点击“开始测速”。
3. 等待进度完成；需要中止时点击“停止”。
4. 查看候选列表，点击结果行只会预选节点。
5. 确认后点击“应用节点”；代理运行时会先提示是否重新连接。

测速进行中和失败后，页面会保留上次成功结果供比较，但不会允许把旧结果应用到代理。

在“首页”点击“测试当前节点”可以只复测已选节点。它会沿用当前协议、端口、URL、线程和下载设置，但不会让批量测速的延迟、丢包、速度或地区筛选条件把该节点过滤掉。开始新的复测时，旧的当前节点结果会先清除；取消或返回不匹配结果时也不会回写旧数据。

如果本地代理正在运行，应用新的内联节点后 ViaSix 会重新启动代理。切换期间连接可能短暂中断。Provider-only 配置不会因应用测速节点而改变订阅服务器。

## 4. 使用本地代理

### 4.1 启动和检查

1. 确认 Mihomo 组件已就绪。
2. 在“首页”选择“规则”“全局”或“直连”。
3. “规则”或“全局”需要有效的内联节点或 Proxy Provider；“直连”不需要服务器配置。
4. 选择“本地代理”或“系统代理”接入方式。“虚拟网卡”目前不可用。
5. 打开本地代理开关。
6. 状态显示运行中后检查目标应用的网络连接。

应用会在首页、设置和菜单栏中显示从本机配置读取的端点。默认地址：

| 类型 | 主机 | 端口 |
| --- | --- | --- |
| HTTP / HTTPS 代理 | `127.0.0.1` | `11451` |
| SOCKS5 代理 | `127.0.0.1` | `11451` |

Mihomo 使用 mixed 入站，因此两种协议共用同一个端口。在“设置 → 本机代理”中修改回环主机或端口后，保存并重新启动代理即可应用。

### 4.2 选择代理模式

三种模式只决定进入 Mihomo 的连接如何出站：

| 模式 | 出站行为 | 启动要求 |
| --- | --- | --- |
| 规则 | 按 YAML 规则和代理组处理；可在最前面加入私有网段直连 | 内联节点或 Proxy Provider |
| 全局 | 使用 Mihomo 全局模式处理进入本地端点的流量 | 内联节点或 Proxy Provider |
| 直连 | 生成 `MATCH,DIRECT`，不载入任何远端代理或 Provider | Mihomo 与有效本机配置 |

如果“规则”配置没有代理组，ViaSix 会根据内联节点和 Provider 创建一个管理组；没有最终规则时追加 `MATCH`。关闭“私有地址直连”后，不再自动插入私有 IPv4/IPv6 网段的直连规则。YAML 中已有的规则仍按顺序保留。

代理模式与网络接入方式相互独立。在“直连”模式下选择系统代理，连接仍会进入本地 Mihomo 端点，但最终直接出站。

### 4.3 使用系统代理

选择“系统代理”后：

- 如果 Mihomo 已运行，ViaSix 会立即尝试应用系统代理；否则会在本地端点启动成功后应用。
- ViaSix 会把当前启用的 macOS 网络服务的 HTTP、HTTPS 和 SOCKS 代理指向本地 mixed 端点。
- 如果网络服务原来启用了 PAC，ViaSix 会在本次会话中暂时停用 PAC，并在恢复时还原原配置。
- 停止代理、切换回本地代理或退出 ViaSix 时，会先恢复启用前保存的 macOS 代理设置；应用异常中断后，下次启动也会尝试完成恢复。
- 如果其他应用在 ViaSix 运行期间修改了某个网络服务，ViaSix 不会用旧快照覆盖该服务的新设置，并会在日志中记录提示。

系统代理不等同于虚拟网卡，只影响遵循 macOS 代理设置的应用。忽略系统代理的应用、部分命令行工具和其他系统流量不会自动进入 ViaSix。

### 4.4 虚拟网卡状态

“虚拟网卡”控制项目前处于不可用状态。即使 Mihomo 本身支持 TUN，ViaSix 当前也不会让用户态 `Runtime/mihomo` 以特权方式运行，不会创建 `utun`，不会修改默认路由或系统 DNS。

虚拟网卡需要固定签名的代理内核、最小权限 helper、上游防回环、路由/DNS 状态验证和崩溃恢复全部就绪后才能开放。当前请使用本地代理或系统代理；它们都不能保证接管全部流量。

### 4.5 在应用中手动设置

不同应用的设置名称可能是“代理服务器”“HTTP Proxy”“SOCKS5”或“网络代理”。将服务器和端口填写为“设置 → 本机代理”里显示的本地端点。

使用“本地代理”接入方式时，只需要在希望使用 ViaSix 的应用中配置。即使选择了系统代理，不遵循 macOS 代理设置的应用仍可能需要单独配置。

### 4.6 在终端中使用

以下示例使用默认端点；如果你修改了本机配置，请替换为“设置 → 本机代理”里显示的值：

```bash
export HTTP_PROXY=http://127.0.0.1:11451
export HTTPS_PROXY=http://127.0.0.1:11451
export ALL_PROXY=socks5h://127.0.0.1:11451
```

使用 `socks5h` 时，支持该写法的程序会通过代理解析域名。关闭终端窗口或执行以下命令可清除这些变量：

```bash
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
```

也可以单次测试：

```bash
curl --proxy http://127.0.0.1:11451 https://example.com
```

### 4.7 检测出口 IP

在首页中选择“检测”：

- 本地代理未运行时，显示当前直连出口。
- 本地代理运行时，通过本地 mixed 端点请求并显示出口信息。
- “自动”由当前网络和检测服务选择可用的地址族，并在结果旁显示 IPv4 或 IPv6。
- “IPv4”或“IPv6”只请求对应地址族；如果当前网络或代理不支持该地址族，检测会失败，不会回退到另一种地址族。

自动模式默认使用 `https://api.myip.la/cn?json`。也可以在“设置 → 应用与数据”中填写其他 HTTP / HTTPS 服务；服务应返回带 `ip` 字段的 JSON，或直接返回一个 IP 文本。

强制 IPv4 和 IPv6 模式分别使用 `https://api-ipv4.ip.sb/ip` 与 `https://api-ipv6.ip.sb/ip`。主检测成功后，ViaSix 使用同一网络路径请求 `https://ipwho.is/<IP>?lang=zh-CN` 补充国家、地区、城市、运营商、ASN 和时区。补充服务失败不会覆盖已经检测到的 IP。

### 4.8 关闭窗口与退出

关闭主窗口不会退出 ViaSix。本地代理和菜单栏入口仍会保留。

需要完全退出时，从菜单栏选择“退出 ViaSix”。ViaSix 会恢复本次会话应用的系统代理设置，停止自己启动的测速和 Mihomo 进程，然后保存设置。

## 5. 自定义组件路径

高级用户可以在“设置 → 运行组件”中指定 CFST 或 Mihomo 可执行文件。留空时，ViaSix 按以下顺序查找：

1. 设置中指定的自定义路径
2. ViaSix 管理的组件
3. Homebrew 常用目录
4. 当前进程的 `PATH`

自定义文件必须与当前 Mac 架构兼容并具有执行权限。自定义 Mihomo 使用 ViaSix 的私有 `Data/Mihomo/` home 和生成配置；不要把同一个 home 同时交给其他 Mihomo 进程。

历史偏好中的 `xrayPath` 不会自动变成 Mihomo 路径。请明确选择真实的 Mihomo 可执行文件。如无特殊需要，建议使用 ViaSix 管理的固定上游组件。

## 6. 应用数据、备份与恢复

数据目录：

```text
~/Library/Application Support/ViaSix/
```

主要内容：

| 路径 | 用途 |
| --- | --- |
| `Data/preferences.json` | 测速参数、组件路径和当前节点 |
| `Data/ip.txt` | IPv4 地址列表 |
| `Data/ipv6.txt` | IPv6 地址列表 |
| `Data/profile.yaml` | Mihomo 节点、Provider、代理组和规则，可能包含凭据 |
| `Data/local-proxy.json` | 本机监听、协议行为、代理模式和网络接入方式 |
| `Data/Mihomo/config.yaml` | 按当前状态生成的 Mihomo 运行配置 |
| `Data/Mihomo/providers/` | Proxy Provider 缓存 |
| `Data/Mihomo/rules/` | Rule Provider 缓存 |
| `Data/system-proxy.json` | 系统代理会话的 macOS 设置恢复快照，恢复完成后删除 |
| `Data/result.csv` | 最近一次测速结果 |
| `Runtime/cfst` | ViaSix 管理的测速组件 |
| `Runtime/mihomo` | ViaSix 管理的用户态代理组件 |
| `Logs/` | 预留的日志目录；当前界面日志只保留本次会话 |

`Data/local-proxy.json` 使用以下字段：

| 字段 | 用途 |
| --- | --- |
| `listenAddress` | 本地 mixed 入站监听地址，只允许回环地址 |
| `port` | 本地 HTTP / SOCKS 共用端口 |
| `udpEnabled` | 是否允许代理节点处理 UDP |
| `sniffingEnabled` | 是否启用 Mihomo 协议嗅探 |
| `bypassPrivateNetworks` | 规则模式下是否自动加入私有网段直连 |
| `logLevel` | Mihomo 日志级别 |
| `routingMode` | `rule`、`global` 或 `direct` |
| `networkAccessMode` | `localProxy`、`systemProxy` 或 `virtualInterface`；当前不允许后者启动 |

`Data/Mihomo/config.yaml` 是派生文件。不要直接编辑它；服务器参数在“设置 → 服务器连接”中管理，本机行为在“设置 → 本机代理”中管理。`system-proxy.json` 只用于恢复操作系统设置，也不应手动修改。

旧版本留下的 `Data/server.json`、`Data/template.json` 和 `Data/config.json` 可能继续存在。ViaSix 只把前两者作为旧 Xray 配置迁移输入，不删除用户文件，也不会把旧 `config.json` 交给 Mihomo 执行。

### 6.1 备份

1. 停止测速和本地代理。
2. 从菜单栏退出 ViaSix。
3. 在 Finder 中选择“前往”>“前往文件夹”。
4. 输入 `~/Library/Application Support/`。
5. 复制整个 `ViaSix` 文件夹到安全位置。

备份可能包含代理凭据、Provider URL 和缓存，应使用受信任的存储位置。

### 6.2 恢复

1. 完全退出 ViaSix。
2. 先备份当前 `ViaSix` 数据文件夹。
3. 将备份内容恢复到 `~/Library/Application Support/ViaSix/`。
4. 重新打开应用并检查组件、代理配置、当前节点和网络接入方式。

跨版本恢复后如果组件不兼容，可以在“设置 → 运行组件”中重新安装。不要把旧 Xray 可执行路径手动填入 Mihomo 路径。

### 6.3 恢复为全新状态

完全退出应用后，把现有 `ViaSix` 数据文件夹移动到其他位置，再重新打开应用。ViaSix 会创建新的默认数据。确认不再需要旧数据前，不要直接删除原文件夹。

默认状态不包含服务器账号。“规则”和“全局”需要重新填写或导入自己的配置；“直连”可以直接使用。

### 6.4 升级应用

1. 完全退出 ViaSix。
2. 备份 Application Support 中的 `ViaSix` 文件夹。
3. 用新版本 `.app` 替换旧版本。
4. 启动后检查运行组件、当前节点、代理配置和网络接入方式。

ViaSix 只自动替换与历史默认内容完全匹配的资源；用户编辑过的列表和配置会保留。旧 Xray JSON 若可兼容，会在首次需要时迁移为 `profile.yaml`，原文件保留供核对。

### 6.5 卸载

- 只删除应用：退出 ViaSix 后移除 `ViaSix.app`。Application Support 中的数据仍会保留。
- 彻底卸载：退出应用并删除 `ViaSix.app`，再删除 `~/Library/Application Support/ViaSix/`。

当前虚拟网卡不可用，因此不会留下 ViaSix 创建的 TUN、默认路由或 DNS 配置。若系统代理会话曾异常中断，建议先重新打开 ViaSix，让应用尝试恢复快照，再执行彻底卸载。

彻底删除前请确认不再需要代理配置或备份。Time Machine、云盘等备份中的副本需按对应产品规则另行清理。

## 7. 排查问题

### 运行组件未就绪

- 确认网络可以访问清单中的 GitHub Releases。
- 在“设置 → 运行组件”中重新选择“安装组件”。
- 如果使用本地导入，确认文件名是 `cfst` 或 `mihomo`、架构正确且可执行。
- 在日志中查看下载、解压、大小或 SHA-256 校验错误。

### 提示代理配置尚未就绪

- 该提示只影响“规则”和“全局”；如果只需要直接出站，可以切换到“直连”。
- 使用“手动配置”、分享链接或高级 YAML 填写自己的连接资料。
- 确认 `proxies` 至少包含一个有效节点，或 `proxy-providers` 至少包含一个 Provider。
- 确认没有保留示例 UUID、密码或 `example.com` TLS 标识。
- Provider-only 配置不要求选择测速节点；内联配置没有测速节点时会使用原 `server`。

### 导入代理配置失败

- 文件导入使用 Mihomo YAML；分享链接请通过“服务器连接 → 分享链接”读取。
- 检查 YAML 顶层是否是映射，`proxies` 和 `rules` 是否为列表。
- HTTP Provider 应包含有效 URL；不要使用任意本地文件 Provider 路径。
- 旧 Xray JSON 只有在能无损识别为受支持的单节点结构时才可迁移。
- 多节点、Provider 或规则配置请使用高级编辑器，不要尝试用单节点表单保存。

### Mihomo 配置校验或启动失败

- 确认“设置 → 本机代理”中的监听端点正确，并且端口没有被其他应用占用。
- 检查 YAML 中的端口、UUID/密码、TLS、Server Name、Host、路径、REALITY 公钥和 Provider URL。
- 确认自定义 Mihomo 是可执行的当前架构版本。
- 查看日志中的 Mihomo `-t` 校验输出。

可在终端中只读检查端口占用：

```bash
lsof -nP -iTCP:11451 -sTCP:LISTEN
```

不要在不清楚进程用途时强制结束它。

### 没有测速结果

- 尝试恢复默认筛选参数。
- 检查地址文件或 CIDR 是否有效。
- 暂时降低下载速度下限或放宽延迟、丢包限制。
- 检查自定义测速 URL 是否可以访问。
- 尝试在 TCPing 和 HTTPing 之间切换。

### 代理已启动但目标应用无法联网

- 使用“本地代理”时，确认目标应用代理类型、主机和端口填写正确。
- 使用“系统代理”时，确认状态显示为已启用，并确认目标应用遵循 macOS 代理设置。
- 使用出口 IP 检测判断通过本地端点的请求是否成功。
- “规则”或“全局”检查自己的 Mihomo 节点、Provider、代理组和规则；“直连”不会使用服务器。
- Provider 配置检查订阅 URL 是否可访问、选择组是否包含 Provider。
- 查看日志中的 Mihomo 输出。

### 系统代理启用或恢复失败

- 确认 Mihomo 已成功运行，并查看日志中的 macOS 网络设置错误。
- 如果系统要求授权，请完成授权后重试。
- 停止代理时如提示无法恢复，ViaSix 会尽量保留本地监听，避免系统应用指向已经关闭的端口；先重试切换到本地代理或停止代理，不要立即强制结束进程。
- 应用异常退出后重新打开 ViaSix，它会尝试使用保存的快照恢复上次设置。
- 如果某个网络服务已被其他应用修改，ViaSix 会保留其当前值；必要时在 macOS“系统设置 → 网络”中核对代理配置。

### 无法选择虚拟网卡

这是当前版本的预期状态。虚拟网卡后端尚未开放，ViaSix 不会通过用户态 Mihomo 修改默认路由或 DNS。需要让更多遵循 macOS 设置的应用自动使用代理时，可以选择“系统代理”；需要全流量接管时请等待经过签名、恢复和真实网络验证的 TUN 实现。

### 出口 IP 检测失败

自动出口检测默认依赖 `api.myip.la`，也可以在“设置 → 应用与数据”中改用其他服务；强制 IPv4 / IPv6 检测依赖 IP.SB 的对应端点，位置补全依赖 `ipwho.is`。服务不可用、DNS、所选地址族或网络策略受限时可能失败。可稍后重试、切换地址族，并结合目标应用的实际联网结果判断。

## 8. 安全建议

- 只使用自己有权访问的服务器、账号和订阅。
- 不要公开 `profile.yaml`、Provider URL、日志中可能出现的连接信息或完整数据备份。
- 不要导入来源不明的 Mihomo 配置或可执行文件。
- 不要把用户可写的 `Runtime/mihomo` 以 root 身份手动运行。
- 正式使用优先选择签名并经过 Apple 公证的 ViaSix 发布包。
- 发现配置泄露后，应立即在服务端撤销或更换相应凭据。

第三方组件及网络服务信息见[第三方声明](../THIRD_PARTY_NOTICES.md)。本机数据和网络连接边界见[隐私说明](../PRIVACY.md)，安全问题报告方式见[安全政策](../SECURITY.md)。
