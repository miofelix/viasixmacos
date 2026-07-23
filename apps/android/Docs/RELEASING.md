# Android 发布说明

各端版本 **独立**。Android 正式 tag 形态：`android/vX.Y.Z`。

## 版本

| 字段 | 位置 |
| --- | --- |
| `versionName` | `apps/android/app/build.gradle.kts` → `defaultConfig.versionName` |
| `versionCode` | 同上 → `versionCode`（每次商店/侧载升级必须 **严格递增**） |

首个正式版：`versionName = 1.0.0`，`versionCode = 1`。

## 签名

见 monorepo 根目录 [`signing/README.md`](../../../signing/README.md)。

- 密钥库：`signing/android/viasix-release.jks`
- 配置：`signing/android/keystore.properties`（本地，不入库）

## 发布前检查

- [ ] 已 bump `versionName` / `versionCode`
- [ ] `CHANGELOG.md` 已写入 `## [android/X.Y.Z]`
- [ ] `node scripts/fetch-mihomo.mjs` 与 `fetch-cfst.mjs` 已准备 arm64 原生库
- [ ] `gradle :core:test :app:test` 通过
- [ ] `gradle :app:assembleRelease` 产出已签名 APK
- [ ] 校验 APK 签名与版本：

```bash
$ANDROID_HOME/build-tools/*/aapt dump badging app-release.apk | head
apksigner verify --print-certs app-release.apk
```

## 构建

```bash
cd apps/android
node scripts/fetch-mihomo.mjs
node scripts/fetch-cfst.mjs
gradle :core:test :app:test --no-daemon
gradle :app:assembleRelease --no-daemon
```

发布文件名规范：`ViaSix-<platform>-<version>.<ext>`

```text
ViaSix-android-<versionName>.apk
ViaSix-android-<versionName>.apk.sha256
```

示例：`ViaSix-android-1.0.0.apk`

## 发布

```bash
git tag -a "android/v1.0.0" -m "Android 1.0.0"
git push origin "android/v1.0.0"
# 或：gh release create android/v1.0.0 --title "ViaSix Android 1.0.0" app-release.apk
```

- 最低系统：Android 8.0（API 26）
- 架构：arm64-v8a（当前正式包）
- 安装方式：侧载 APK；未上架 Play 时需允许「未知来源」
