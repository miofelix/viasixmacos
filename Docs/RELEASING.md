# ViaSix 发布指南

本文面向负责构建和发布 ViaSix 的维护者。普通用户请阅读 [README](../README.md) 和 [用户指南](USER_GUIDE.md)。

## 目录

- [发布模型](#发布模型)
- [发布前检查](#发布前检查)
- [构建和测试](#构建和测试)
- [Developer ID 签名](#developer-id-签名)
- [Apple 公证](#apple-公证)
- [Gatekeeper 与最终验证](#gatekeeper-与最终验证)
- [发布产物](#发布产物)
- [第三方组件义务](#第三方组件义务)
- [发布后](#发布后)

## 发布模型

ViaSix 会启动外部网络工具，并在 Application Support 中维护运行组件，因此当前发布模型是：

- Developer ID Application 签名
- Hardened Runtime
- Apple 公证与 ticket 装订
- 非 Mac App Store 沙盒分发

应用不安装系统扩展或网络扩展。应用包包含 LaunchDaemon helper、管理员安装器，以及与当前应用架构一致的固定 Mihomo v1.19.29。正式签名版本由 `SMAppService` 管理，管理员可能需要在系统设置批准；本地 ad-hoc 构建则通过管理员安装器创建 root-owned 固定副本，仅用于本机调试。应用仍可用登录用户权限运行本机代理；虚拟网卡只使用 app bundle 内固定签名、root-only 安装的 Mihomo，并在路由、DNS、进程监督与恢复验证通过后开放。helper 不能执行用户目录中的二进制。

## 发布前检查

发布前确认：

- 工作树中的发布内容已经审阅
- `Packaging/Info.plist` 中的 `CFBundleShortVersionString` 与 `CFBundleVersion` 已更新
- `CHANGELOG.md` 已把“未发布”内容固化为本次版本并写明发布日期
- 默认 `local-proxy.json` 只监听回环地址并使用 `localProxy` 接入方式；bundle 不包含 `profile.yaml`、`server.json` 或 `template.json`
- `RuntimeManifest.swift` 与 `Scripts/fetch-mihomo.sh` 中的固定 Mihomo URL、压缩包 SHA-256、payload 大小和 SHA-256 一致且有效
- `THIRD_PARTY_NOTICES.md` 和 `ThirdPartyLicenses/` 与组件清单一致
- 根目录 `LICENSE` 与应用包中的 MIT License 副本一致
- 用户指南与当前界面名称一致
- `make check` 和 `make app` 通过
- LaunchDaemon plist、Mihomo、helper、管理员安装器与主应用使用预期 identifier；非 ad-hoc 构建使用相同 Team ID，嵌套签名逐项通过
- `PrivilegedRuntime.plist` 的版本、架构、相对路径、identifier、签名后 SHA-256 与 CDHash 均和嵌入 Mihomo 一致
- app 公证成功；包含 LaunchDaemon 的构建不得作为“未公证也可用”的正式产物发布
- 应用包不包含 Xray 可执行文件、数据文件或 MPL 许可证；离线许可证包含 Mihomo GPL-3.0
- 支持的每种 CPU 架构均经过实际验证
- 待发布提交中不包含本机绝对路径、真实凭据或未审阅的大文件

ViaSix 自身基于 [MIT License](../LICENSE) 发布；第三方声明只覆盖对应的第三方组件，不能替代 ViaSix 自身许可证。

## 构建和测试

从干净的发布候选版本开始：

```bash
make clean
make check
```

生成本地 ad-hoc 签名包并执行 bundle 验证。默认会从固定 HTTPS 地址下载当前架构的 Mihomo，并在解压前后校验固定摘要；也可以用已验证的上游二进制避免重复下载：

```bash
VIASIX_MIHOMO_SOURCE=/absolute/path/to/mihomo-v1.19.29 make app-debug
```

`VIASIX_MIHOMO_SOURCE` 不是跳过校验的开关。指定的文件仍须匹配固定 payload 大小、SHA-256、Mach-O 架构和版本输出。未设置时，打包脚本只复用每次都能重新通过摘要校验的用户私有缓存。

也可以生成优化后的本地 ad-hoc release 包：

先读取唯一版本来源，再让验证脚本核对版本、build number 和当前架构：

```bash
viasix_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)
viasix_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Packaging/Info.plist)
viasix_arch=$(uname -m)

VIASIX_EXPECTED_VERSION="$viasix_version" \
VIASIX_EXPECTED_BUILD_VERSION="$viasix_build" \
VIASIX_EXPECTED_ARCHITECTURE="$viasix_arch" \
make app
```

生成位置：

```text
dist/ViaSix.app
```

`make app` 和 `make app-debug` 构建的是当前 Swift 工具链目标架构的应用程序，并只嵌入同一架构的 Mihomo。不要仅凭一台 arm64 Mac 的结果声明同一个 bundle 是 Universal Binary。发布 arm64 与 x86_64 构建时，应分别验证主程序、helper、Mihomo 和对应安装流程；如需通用二进制，应先扩展打包流程和运行时清单格式，不能把两个薄架构运行时直接混入当前 bundle。

记录 `swift --version`、`xcodebuild -version`、`sw_vers`、`uname -m` 和发布提交。CI 固定最低规范工具链用于一致性检查，正式产物仍应在受控发布机上生成。

检查主程序架构：

```bash
file dist/ViaSix.app/Contents/MacOS/ViaSix
lipo -info dist/ViaSix.app/Contents/MacOS/ViaSix
```

## Developer ID 签名

确保钥匙串中存在有效的 “Developer ID Application” 证书：

```bash
security find-identity -v -p codesigning
```

指定签名身份后重新打包：

```bash
VIASIX_CODESIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID)" make app
```

打包脚本按以下固定顺序处理嵌套代码：

1. 校验并签名 `Contents/Library/HelperTools/com.felix.viasix.mihomo`，identifier 为 `com.felix.viasix.mihomo`。
2. 签名 `Contents/Library/HelperTools/com.felix.viasix.tun-helper`。
3. 签名 `Contents/Library/HelperTools/com.felix.viasix.tun-installer`。
4. 根据签名后的 Mihomo 生成 `Contents/Resources/PrivilegedRuntime.plist`。
5. 最后签名外层 app，使运行时清单受 app resource seal 保护。

使用非 ad-hoc 身份时，Mihomo、helper、installer 与 app 都启用 Hardened Runtime 和可信时间戳。不要使用 `codesign --deep --sign` 代替确定的嵌套签名顺序。未提供签名身份的本地构建通过 root-owned 固定副本、已安装 helper 的精确 CDHash、授权 UID 和协议检查开放本机 TUN 调试；普通 App 重编不应触发再次授权。它没有可信 Team ID，不得作为对外分发产物。

验证签名：

```bash
codesign --verify --deep --strict --verbose=2 dist/ViaSix.app
codesign -d --verbose=4 dist/ViaSix.app
codesign --verify --strict --verbose=2 \
  dist/ViaSix.app/Contents/Library/HelperTools/com.felix.viasix.tun-helper
codesign -d --verbose=4 \
  dist/ViaSix.app/Contents/Library/HelperTools/com.felix.viasix.tun-helper
codesign --verify --strict --verbose=2 \
  dist/ViaSix.app/Contents/Library/HelperTools/com.felix.viasix.mihomo
codesign -d --verbose=4 \
  dist/ViaSix.app/Contents/Library/HelperTools/com.felix.viasix.mihomo
plutil -p dist/ViaSix.app/Contents/Resources/PrivilegedRuntime.plist
```

确认主应用、helper 与 Mihomo 输出中的 Team Identifier 相同，identifier 分别为 `com.felix.viasix`、`com.felix.viasix.tun-helper` 和 `com.felix.viasix.mihomo`，并核对 Timestamp、Runtime Version 和 Authority。`make verify-app` 还会复核运行时清单中的 SHA-256 与 CDHash。

## Apple 公证

首次使用时，可把公证凭据保存到钥匙串：

```bash
xcrun notarytool store-credentials "viasix-notary"
```

将应用压缩为保留 bundle 元数据且包含版本和架构的 ZIP：

```bash
viasix_artifact="dist/ViaSix-${viasix_version}-macOS-${viasix_arch}.zip"
ditto -c -k --keepParent dist/ViaSix.app "$viasix_artifact"
```

提交公证并等待结果：

```bash
xcrun notarytool submit "$viasix_artifact" \
  --keychain-profile "viasix-notary" \
  --wait
```

公证成功后装订 ticket：

```bash
xcrun stapler staple dist/ViaSix.app
xcrun stapler validate dist/ViaSix.app
```

再次生成最终 ZIP，确保分发包包含已装订的应用：

```bash
ditto -c -k --keepParent dist/ViaSix.app "$viasix_artifact"
```

## Gatekeeper 与最终验证

```bash
codesign --verify --deep --strict --verbose=2 dist/ViaSix.app
spctl --assess --type execute --verbose=4 dist/ViaSix.app
make verify-app
```

建议在一台没有开发环境和旧 ViaSix 数据的受支持 Mac 上验证：

1. 从最终 ZIP 解压。
2. 首次启动没有异常 Gatekeeper 提示。
3. 可以安装当前架构的上游组件。
4. 默认本机配置只监听回环地址、网络接入方式为 `virtualInterface`，首次运行不包含服务器凭据或订阅。
5. 使用单节点 Mihomo YAML 和 `x-viasix` selected-IP YAML 验证导入；确认受支持的单节点 YAML 可在可视化表单中查看、修改并保存，且 selected-IP 模板不会写回节点地址。
6. `rule` / `global` 只保留第一个可注入地址的内联代理并注入当前 IPv6；确认 Provider-only、IPv4 节点和缺少当前 IPv6 节点均被拒绝。
7. “直连”运行配置不包含代理、Provider、代理组或远端规则。
8. HTTP 与 SOCKS5 均可通过配置中显示的回环端点使用。
9. 系统代理启用失败会回滚，Mihomo 意外退出会恢复系统代理；外部修改不被旧快照覆盖。
10. 菜单栏重新打开窗口、停止任务和退出均正常，退出后没有遗留 ViaSix 启动的进程或端口监听。
11. 从旧版本升级时不会迁移旧 Xray 或旧本机代理配置；旧配置解码失败时按错误明确提示，不静默兼容。
12. 从 `/Applications` 启动，helper 正确区分“未注册”“等待系统设置批准”“已启用”和“不可用”；批准服务并安装固定签名运行时后，验证虚拟网卡可选择、启动、停止、异常恢复和退出清理；测试完成后正常注销服务并确认无残留进程、路由或 DNS 状态。

## 发布产物

推荐至少发布：

- `ViaSix-<version>-macOS-arm64.zip`
- `ViaSix-<version>-macOS-x86_64.zip`（实际完成该架构验证时）
- 每个 ZIP 的 SHA-256
- 发布说明
- 第三方声明
- ViaSix 自身许可证

生成校验值：

```bash
shasum -a 256 "$viasix_artifact"
```

发布说明应面向用户，包含：

- 主要新功能和可见变化
- 配置或数据迁移说明
- 最低 macOS 版本
- 已知限制
- 是否需要重新安装运行组件

不要在发布说明中泄露测试账号、服务器地址、签名凭据或内部路径。

## 第三方组件义务

ViaSix 按固定清单取得第三方上游发布包，并在应用包中提供离线许可证正文。Mihomo 作为固定签名的嵌套代码直接进入应用包；CloudflareSpeedTest 仍由普通用户权限的组件管理流程安装。两条供应链都必须保留上游版本、压缩包与 payload 摘要以及许可证审计记录。

CloudflareSpeedTest 与 Mihomo 均使用 GPL-3.0。ViaSix 分发包直接包含 Mihomo 二进制，因此正式发布时必须完成对应源代码提供方式和声明义务审计；仅附许可证正文或项目链接不应被视为已经自动满足全部义务。权威版本、源码和许可证链接见[第三方声明](../THIRD_PARTY_NOTICES.md)。

## 发布后

- 为发布提交创建并验证与版本一致的签名或带注释 Git tag，例如 `v1.2.3`
- 从公开下载地址重新下载一次最终产物并校验 SHA-256
- 验证公证 ticket 和 Gatekeeper
- 确认第三方下载 URL 仍可访问
- 记录版本、提交、签名身份、notary submission ID 和产物哈希
- 保留可复现发布所需的源代码和声明
