# mihomo-config（跨端投影约定）

本包**当前不提供统一运行时实现**，而是描述各端必须遵守的投影语义，并指向 monorepo 契约：

```text
contracts/fixtures/mihomo-config/cases/*
```

## 各端实现位置

| 平台 | 实现 | 测试 |
| --- | --- | --- |
| macOS | `apps/macos/.../ViaSixMihomoConfig` | `ContractFixtureTests` |
| Windows | `apps/windows/src-tauri/src/projection` | `cargo test` |
| Android | `apps/android/core/.../MihomoProjection` | `gradle :core:test` |

一键：`make projection-test`

## 何时抽共享库

当下列情况频繁出现时，再将实现收敛为 Rust/Go 单库 + FFI：

1. 三端 fixture 漂移（同一 case 不同结果）
2. 投影规则每周多次变更
3. 安全审计要求单一解析实现

在此之前，**以 contracts fixtures 为唯一真相**，各端原生实现即可。

## 校验

```bash
node packages/mihomo-config/scripts/validate-cases.mjs
```
