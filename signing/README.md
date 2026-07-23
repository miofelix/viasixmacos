# 签名材料（Signing）

各端 **独立版本、独立签名**。私钥与口令保存在本目录的机器本地文件中，**不得提交到 Git**。

## Android

| 文件 | 是否提交 | 说明 |
| --- | --- | --- |
| `android/viasix-release.jks` | 否 | 正式版 release 密钥库（PKCS12） |
| `android/keystore.properties` | 否 | `storeFile` / 口令 / alias |
| `android/keystore.properties.example` | 是 | 配置模板 |
| `android/viasix-release.cer` | 是 | 公钥证书（仅用于校验指纹） |

### 本地配置

```bash
cp signing/android/keystore.properties.example signing/android/keystore.properties
# 编辑 storeFile（建议绝对路径）与口令，或使用已有 jks
```

### 构建已签名 release APK

```bash
cd apps/android
# 如缺原生库：node scripts/fetch-mihomo.mjs && node scripts/fetch-cfst.mjs
gradle :app:assembleRelease --no-daemon
```

产物：

```text
apps/android/app/build/outputs/apk/release/app-release.apk
```

### 证书指纹（1.0.0 正式签名）

```text
SHA-256: B6:01:4A:11:69:77:2F:90:C9:45:96:F4:30:6E:8F:E5:2E:D9:D9:54:33:77:F6:43:8D:FE:FF:30:91:17:45:F6
Alias: viasix
```

### 备份

丢失 `viasix-release.jks` 或口令后，无法对同一 `applicationId`（`dev.viasix.app`）发布可覆盖升级的后续版本。请将 jks + properties **离线加密备份**。

## macOS

正式对外分发需要：

1. **Developer ID Application** 证书（钥匙串）
2. Hardened Runtime + 嵌套签名
3. `notarytool` 公证与 `stapler` 装订

环境变量：

```bash
export VIASIX_CODESIGN_IDENTITY="Developer ID Application: … (TEAMID)"
```

本仓库 **不** 存放 Apple `.p12` / 公证 App 专用密码。详见 [`apps/macos/Docs/RELEASING.md`](../apps/macos/Docs/RELEASING.md)。

当前维护机若无 Developer ID，只能产出 **ad-hoc** 签名包，可用于自测，**不能**通过 Gatekeeper 直接分发为「已公证」安装包。
