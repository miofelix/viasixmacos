# Monorepo 布局

ViaSix 采用 **契约中心 + 多端壳**（模式 A）结构：共享配置与行为约定，各端独立实现 UI 与特权网络接入。

```text
viasix/
├── contracts/           # 跨端 schema 与黄金 fixture
├── packages/            # 共享约定与校验（mihomo-config 等）
├── apps/
│   ├── macos/           # SwiftPM + SwiftUI + XPC TUN helper
│   ├── windows/         # 桌面壳骨架（用户态 mihomo → 后续 TUN）
│   └── android/         # Kotlin 壳骨架（VpnService）
├── server/              # Cloudflare Pages 等与客户端无关的服务
├── docs/                # 产品与架构文档
├── toolchains/          # 跨端工具脚本（内核拉取等，渐进迁入）
└── .github/workflows/   # 按路径过滤的 CI
```

## 依赖方向

```text
apps/*  →  contracts（行为对齐）
apps/*  ↛  其他 apps/*（禁止端到端直接依赖）
packages/* → contracts；不得依赖 apps/*
```

## 平台能力矩阵（产品）

| 能力 | macOS | Windows | Android |
| --- | --- | --- | --- |
| 用户态 mihomo | ✓ | ✓（规划） | ✓（规划） |
| 系统代理 | ✓ | ✓（规划） | 不适用 |
| 虚拟网卡 | XPC helper + utun | Service + Wintun（二期） | VpnService |
| IPv6 优选 / 投影 | ✓ | 契约对齐 | 契约对齐 |

详见 [跨平台路线](roadmap.md)。
