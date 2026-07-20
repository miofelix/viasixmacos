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

应用不需要管理员权限，也不安装系统扩展或网络扩展。

## 发布前检查

发布前确认：

- 工作树中的发布内容已经审阅
- `Packaging/Info.plist` 中的 `CFBundleShortVersionString` 与 `CFBundleVersion` 已更新
- `CHANGELOG.md` 已把“未发布”内容固化为本次版本并写明发布日期
- 默认 `server.json`、`local-proxy.json` 和 `template.json` 不包含真实 IP、UUID、域名、密钥或账号资料
- `RuntimeManifest.swift` 中的组件 URL 和 SHA-256 有效
- `THIRD_PARTY_NOTICES.md` 和 `ThirdPartyLicenses/` 与组件清单一致
- 根目录 `LICENSE` 与应用包中的 MIT License 副本一致
- 用户指南与当前界面名称一致
- `make check` 和 `make app` 通过
- 支持的每种 CPU 架构均经过实际验证
- 待发布提交中不包含本机绝对路径、真实凭据或未审阅的大文件

ViaSix 自身基于 [MIT License](../LICENSE) 发布；第三方声明只覆盖对应的第三方组件，不能替代 ViaSix 自身许可证。

## 构建和测试

从干净的发布候选版本开始：

```bash
make clean
make check
```

生成本地 ad-hoc 签名包并执行 bundle 验证：

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

`make app` 构建的是当前 Swift 工具链目标架构的应用程序。不要仅凭一台 arm64 Mac 的结果声明同一个 bundle 是 Universal Binary。发布 arm64 与 x86_64 构建时，应分别验证二进制架构和对应组件安装流程；如需通用二进制，应先扩展打包流程并验证 `lipo` 合并结果。

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

打包脚本会为非 ad-hoc 身份启用 Hardened Runtime 和时间戳。

验证签名：

```bash
codesign --verify --deep --strict --verbose=2 dist/ViaSix.app
codesign -d --verbose=4 dist/ViaSix.app
```

确认输出中的 Team Identifier、Timestamp、Runtime Version 和 Authority 符合预期。

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
4. 默认模板不包含真实连接资料，并明确要求用户导入自己的配置。
5. 导入有效测试配置后可以测速、选择节点并启动代理。
6. HTTP 与 SOCKS5 均可通过配置中显示的回环端点使用。
7. 菜单栏重新打开窗口、停止任务和退出均正常。
8. 退出后没有遗留 ViaSix 启动的进程或端口监听。
9. 从旧版本升级时只迁移未修改的历史默认资源。

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

ViaSix 默认按需下载第三方上游发布包，并在应用包中提供离线许可证正文。若未来把第三方二进制直接放入 ViaSix 分发包，必须重新审查相应许可证义务。

特别是 CloudflareSpeedTest 使用 GPLv3；与其二进制一起分发时，发布者需要满足相应源码和声明要求。Xray-core 使用 MPL 2.0。权威链接见 [第三方声明](../THIRD_PARTY_NOTICES.md)。

## 发布后

- 为发布提交创建并验证与版本一致的签名或带注释 Git tag，例如 `v1.2.3`
- 从公开下载地址重新下载一次最终产物并校验 SHA-256
- 验证公证 ticket 和 Gatekeeper
- 确认第三方下载 URL 仍可访问
- 记录版本、提交、签名身份、notary submission ID 和产物哈希
- 保留可复现发布所需的源代码和声明
