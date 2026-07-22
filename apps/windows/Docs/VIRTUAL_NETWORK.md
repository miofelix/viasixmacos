# Windows 虚拟网卡（Mihomo TUN + Wintun）

## 当前实现

ViaSix Windows **不自建独立 Windows Service**，而是：

1. `pnpm prebuild` 下载 `wintun.dll` 到 `src-tauri/sidecar/`
2. UI 打开「虚拟网卡」→ `set_virtual_network(true)`
3. 启动 Mihomo 时：
   - 将 `wintun.dll` 复制到 mihomo 同目录
   - 运行配置中 `tun.enable: true`（mixed stack + auto-route + fake-ip DNS）
4. **由 Mihomo 加载 Wintun** 创建虚拟网卡并接管路由

| 项 | 状态 |
| --- | --- |
| 投影 `tun` + DNS | ✓ |
| 拉取 / 打包 `wintun.dll` | ✓（`fetch-wintun.mjs`） |
| UI 开关 | ✓（有 dll 时可开） |
| 独立特权 Service / 签名 helper | 未做（Mihomo 进程内 TUN） |

## 权限

Windows 上创建 TUN / 改路由 **通常需要管理员权限**。若启动失败，请：

- 以管理员运行 ViaSix，或
- 先关闭 TUN，仅用系统代理 + mixed 端口

## 与 macOS 差异

| | macOS | Windows（本实现） |
| --- | --- | --- |
| 特权组件 | 独立 TunHelper + XPC | 无独立 helper |
| 网卡 | utun | Wintun（mihomo 驱动） |
| 信任边界 | helper 固定签名 mihomo | 用户态 mihomo + 同目录 wintun |

更强的 Service 隔离与 Authenticode 可作为后续增强，**不阻塞**本路径使用。
