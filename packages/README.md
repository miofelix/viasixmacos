# Shared packages

跨端可复用资产。

| 路径 | 状态 | 说明 |
| --- | --- | --- |
| [mihomo-config](mihomo-config/) | 约定 + 校验脚本 | 投影语义文档；`validate-cases.mjs` |
| （未来）`domain` | 未建 | 就绪条件 / 错误码纯逻辑 |

**原则**：共享库落地前，行为以 `contracts/` fixtures 为准；各端可有原生实现，但必须通过同一套 case。
