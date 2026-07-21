# 参与 ViaSix 开发

感谢你愿意改进 ViaSix。本文说明协作流程；构建环境和实现约定见[开发说明](Docs/DEVELOPMENT.md)，模块边界见[架构说明](Docs/ARCHITECTURE.md)。

> [!NOTE]
> ViaSix 基于 [MIT License](LICENSE) 发布。提交贡献即表示你有权提供相关内容，并同意该贡献按同一许可证授权；第三方内容仍须遵循其原有许可证。

## 提交改动前

- 普通缺陷和功能建议应通过仓库 Issue 讨论；安全问题不要公开提交，参见[安全政策](SECURITY.md)。
- 一个变更尽量只解决一个明确问题，避免同时混入无关重构。
- 涉及进程生命周期、配置迁移、运行组件或网络行为时，先说明失败和回滚路径。

## 本地工作流

```bash
make format
make check
```

涉及应用资源、Info.plist、图标或打包脚本时，还应运行：

```bash
make app
```

常用命令可在 [Makefile](Makefile) 中查看。

## 代码与测试

- Swift 代码由仓库根目录的 `.swift-format` 统一格式化，不手工维护另一套冲突规则。
- 新功能和缺陷修复应覆盖成功、失败、取消、重复调用及应用退出等相关路径。
- 不允许按进程名全局结束第三方进程；只能管理 ViaSix 自己创建并仍持有的进程组。
- 不要在源码、测试、日志、截图或提交历史中加入真实 UUID、域名、服务器、令牌、签名凭据或代理配置。
- 修改默认资源时必须证明不会覆盖用户已经编辑的文件，并补充迁移测试。

## 提交和 Pull Request

提交信息沿用 Conventional Commits 风格，例如：

```text
feat: add runtime status refresh
fix: preserve customized proxy template
docs: clarify release verification
```

Pull Request 应说明：

- 解决的问题和用户可见影响
- 已执行的验证命令
- 数据迁移、网络、进程或发布风险
- 需要同步更新的文档、版本和第三方声明

提交前请完成仓库的 Pull Request 检查清单并确保 CI 通过。

## 需要同步更新的内容

- 更新组件版本：`RuntimeManifest.swift`、测试、`THIRD_PARTY_NOTICES.md` 和发布说明。
- 更新应用版本：`Packaging/Info.plist`、`CHANGELOG.md`、发布产物名称和 Git tag。
- 更新用户流程或界面文案：`README.md`、`Docs/USER_GUIDE.md` 及相关截图或帮助内容。
- 更新存储、网络端点或遥测行为：`PRIVACY.md` 和安全说明。
