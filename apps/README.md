# Applications

| 路径 | 平台 | 状态 |
| --- | --- | --- |
| [macos](macos/) | macOS 14+ | 可构建（现有产品） |
| [windows](windows/) | Windows | MVP（Tauri + 投影 + 代理/出口/测速） |
| [android](android/) | Android | MVP 骨架（投影 + VpnService） |

各应用**不得**相互 import。共享行为只通过 [`../contracts`](../contracts) 对齐。
