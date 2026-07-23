# Windows 发布说明

## 产物

| 产物 | 说明 |
| --- | --- |
| NSIS installer | 发布名建议 `ViaSix-windows-<version>.exe`（构建机原始名多为 `ViaSix_*_x64-setup.exe`） |
| 裸 exe | `ViaSix.exe`（调试/便携参考，一般不单独作为正式下载名） |

GitHub Actions：`.github/workflows/windows-build.yml`  
触发：`apps/windows/**` 变更、PR、或手动 `workflow_dispatch`。

## 本地打包

要求：

- Windows 10/11 x64
- Rust stable (MSVC)
- Node 22 + pnpm
- WebView2（系统自带或安装程序会引导）

```powershell
cd apps/windows
pnpm install
pnpm prebuild
pnpm app:build:ci
```

NSIS 输出目录（之一）：

```text
src-tauri/target/release/bundle/nsis/
src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/
```

## Sidecar

`pnpm prebuild` 将 mihomo / CFST 下载到 `src-tauri/sidecar/`。  
`tauri.conf.json` 的 `bundle.resources` 会把 `sidecar/*` 打进安装包；运行时从 Resource 目录解析。

## 版本

同步 bump：

- `apps/windows/package.json`
- `apps/windows/src-tauri/Cargo.toml`
- `apps/windows/src-tauri/tauri.conf.json`

## 签名

当前 CI **不** 做 Authenticode 签名。正式发布前应配置证书与 `tauri` Windows 签名字段。
