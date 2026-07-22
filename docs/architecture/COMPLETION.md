# 跨平台范围完成说明

本文界定「全部完成」在本 monorepo 中的含义，以及仍依赖外部密钥/可选增强的项。

## 范围内已完成

| 能力 | macOS | Windows | Android |
| --- | --- | --- | --- |
| Monorepo + contracts fixtures | ✓ | ✓ | ✓ |
| IPv6 投影 | ✓ | ✓（共享 Rust crate） | ✓（Kotlin） |
| 用户态 Mihomo | ✓ | ✓ | ✓ |
| 系统代理 | ✓ | ✓ | N/A |
| 虚拟网卡 / VPN | ✓ XPC+utun | ✓ Mihomo TUN+Wintun | ✓ VpnService+转发 |
| 测速 | ✓ CFST | ✓ CFST | —（可后续） |
| 流量展示 | ✓ | ✓ | ✓ 累计 |
| 会话偏好 | ✓ | ✓ | ✓ |
| 安装包/CI | ✓ app | ✓ NSIS workflow | ✓ assembleDebug |

## 范围外 / 需仓库外配置

| 项 | 原因 |
| --- | --- |
| Authenticode / Apple 公证 / Play 签名 | 需要你的证书与密钥，无法在开源仓内「完成」 |
| 独立 Windows Service 特权隔离 | 可选安全增强；当前为进程内 Mihomo+Wintun |
| Swift/Kotlin 共用 Rust FFI | 可选；三端 fixtures 已对齐 |
| Android hev 生产级 tun2socks | 可选；当前用户态 TCP/DNS 转发为可用 MVP |
| Linux GUI 独立产品线 | 未单列；Windows Tauri 栈可扩展 |

## 验证

```bash
make contracts-check
make shared-test
make projection-test   # 较慢：含 macOS swift test
make windows-test
make android-test
```
