# ViaSix for macOS

ViaSix 是参考 `ipv6-plan` 业务逻辑重写的原生 macOS 客户端。项目使用 SwiftUI 构建界面，并将测速、配置生成、Xray 生命周期、运行组件安装和数据持久化拆分为独立模块。

## 环境要求

- macOS 14 或更高版本
- Xcode 16 或更高版本（当前使用 Xcode 26.6 验证）
- Swift 6

## 本地开发

```bash
make build
make test
swift run ViaSix
```

生成可双击运行的 `.app`：

```bash
make app
open dist/ViaSix.app
```

## 目录结构

```text
Sources/
  ViaSixCore/       纯业务模型、解析器和服务
  ViaSixApp/        SwiftUI 界面与 macOS 生命周期
Tests/
  ViaSixCoreTests/  核心逻辑测试
Packaging/          App bundle 元数据
Scripts/            构建与打包脚本
```

## 实现阶段

1. 原生应用骨架与规范化工程
2. 数据模型、参数持久化、CSV/配置解析
3. CloudflareSpeedTest 进程与进度管理
4. Xray 运行、节点切换、出口 IP 检测
5. 运行组件安装、菜单栏、日志和完整 UI
6. 功能对照测试、打包与文档

第三方运行组件由用户在应用内从其官方 GitHub Releases 下载，或指定本机已有可执行文件；组件不会直接提交到本仓库。

