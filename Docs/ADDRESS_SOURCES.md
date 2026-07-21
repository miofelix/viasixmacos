# 内置地址列表来源

本文记录 `Sources/ViaSixCore/Resources/` 中默认地址列表的来源、快照时间和更新流程，避免无法追溯的手工修改。

## 当前快照

| 文件 | 来源 | 快照日期 | 仓库文件 SHA-256 |
| --- | --- | --- | --- |
| `ip.txt` | [XIU2/CloudflareSpeedTest v2.3.5 ip.txt](https://raw.githubusercontent.com/XIU2/CloudflareSpeedTest/v2.3.5/ip.txt) | 2026-07-20 | `bfdb7ca772dd3f04ad531621de818bff15271c1a04eb632688cd31ac9ef55e8d` |
| `ipv6.txt` | [Cloudflare IPv6 ranges](https://www.cloudflare.com/ips-v6) | 2026-07-20 | `e82386bc5ad5aaf33650db82952b513ea9d1946e7f1908c5ea5fb7de20a7e39a` |

仓库统一使用 LF 换行和末尾换行，因此哈希不一定与上游 HTTP 响应的原始字节完全一致。CloudflareSpeedTest 是 XIU2 维护的独立第三方项目，并非 Cloudflare 官方产品。

## 更新流程

1. 从上表的权威来源下载到临时目录，不直接覆盖仓库文件。
2. 核对来源项目、版本或快照日期，并审查新增、删除和范围扩大的影响。
3. 规范化为 UTF-8、LF 换行和一个末尾换行。
4. 更新本表的来源、日期和 SHA-256。
5. 更新默认资源迁移哈希和测试；只迁移与旧默认内容完全匹配的用户文件。
6. 运行 `make format`、`make check` 和 `make app`。

不要把第三方维护的地址列表描述成 ViaSix 对地址所有权、可用性或使用许可的保证。大范围 CIDR 会增加测速耗时和网络负载，更新时应结合产品默认参数审查。
