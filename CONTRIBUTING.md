# 参与 ViaSix 开发

感谢你愿意改进 ViaSix。本文说明协作流程。

- macOS 构建与实现约定：[apps/macos/Docs/DEVELOPMENT.md](apps/macos/Docs/DEVELOPMENT.md)
- 模块边界：[apps/macos/Docs/ARCHITECTURE.md](apps/macos/Docs/ARCHITECTURE.md)
- Monorepo 布局：[docs/architecture/repo-layout.md](docs/architecture/repo-layout.md)

> [!NOTE]
> ViaSix 基于 [MIT License](LICENSE) 发布。提交贡献即表示你有权提供相关内容，并同意该贡献按同一许可证授权；第三方内容仍须遵循其原有许可证。

## 提交改动前

- 普通缺陷和功能建议应通过仓库 Issue 讨论；安全问题不要公开提交，参见[安全政策](SECURITY.md)。
- 一个变更尽量只解决一个明确问题，避免同时混入无关重构。
- 涉及进程生命周期、配置迁移、运行组件或网络行为时，先说明失败和回滚路径。
- **跨端行为**（配置投影、就绪条件、`local-proxy` 字段）必须先更新 [`contracts/`](contracts/)，再改各端实现。

## 本地工作流

仓库根目录：

```bash
make contracts-check    # schema + fixture case 结构
make projection-test    # macOS + Windows + Android 投影契约
make check              # contracts + macOS + windows-test + android-test
make check-all          # 另含平台骨架校验
make macos-app          # 打包 macOS 应用
make windows-test
make android-test
make android-assemble   # 需 Android SDK
```

仅改 macOS 时也可：

```bash
cd apps/macos
make format
make check
make app
```

## 代码与测试

- Swift 代码由 `apps/macos/.swift-format` 统一格式化。
- 新功能和缺陷修复应覆盖成功、失败、取消、重复调用及应用退出等相关路径。
- 不允许按进程名全局结束第三方进程；只能管理 ViaSix 自己创建并仍持有的进程组。
- 不要在源码、测试、日志、截图或提交历史中加入真实 UUID、域名、服务器、令牌、签名凭据或代理配置。
- 修改默认资源时必须证明不会覆盖用户已经编辑的文件，并补充迁移测试。
- 各 `apps/*` 之间禁止直接依赖；共享只通过 `contracts/`（及未来的 `packages/`）。

## 提交和 Pull Request

提交信息沿用 Conventional Commits 风格，例如：

```text
feat: add runtime status refresh
fix: preserve customized proxy template
docs: clarify release verification
chore: scaffold windows app skeleton
```

Pull Request 应说明：

- 解决的问题和用户可见影响
- 已执行的验证命令
- 数据迁移、网络、进程或发布风险
- 需要同步更新的文档、版本和第三方声明
- 是否影响 `contracts/` 或其他平台骨架

## 需要同步更新的内容

- 更新组件版本：`RuntimeManifest.swift`、测试、`THIRD_PARTY_NOTICES.md` 和发布说明。
- 更新应用版本：`apps/macos/Packaging/Info.plist`、`CHANGELOG.md`、发布产物名称和 Git tag。
- 更新用户流程或界面文案：`README.md`、`apps/macos/Docs/USER_GUIDE.md` 及相关截图或帮助内容。
- 更新存储、网络端点或遥测行为：`PRIVACY.md` 和安全说明。
- 更新跨端配置语义：`contracts/schemas`、`contracts/fixtures` 与各端测试。
