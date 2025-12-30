# 06 - Shared Spaces 脚本

为每个项目创建 Shared Space，实现团队协作。

## 前置条件

1. 已完成 `04-sagemaker-domain/` Domain 创建
2. 已完成 `05-user-profiles/` User Profiles 创建
3. 已配置 `.env.shared` 中的项目信息

## 快速开始

```bash
# 一键执行
./setup-all.sh

# 验证
./verify.sh
```

## 创建的资源

每个项目对应一个 Shared Space：

| Space Name | 团队 | 项目 | Owner | 成员 |
|------------|------|------|-------|------|
| space-rc-fraud-detection | 风控 | fraud-detection | profile-rc-alice | bob, carol |
| space-algo-recommendation-engine | 算法 | recommendation-engine | profile-algo-david | eve |
| ... | ... | ... | ... | ... |

## 命名规范

```
Space 名称: space-{team}-{project}

示例:
  space-rc-fraud-detection       # 风控 - 欺诈检测项目
  space-algo-recommendation-engine  # 算法 - 推荐引擎项目
```

## 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `SPACE_EBS_SIZE_GB` | `50` | 每个 Space 的 EBS 存储大小 |

## 脚本说明

| 脚本 | 功能 |
|------|------|
| `setup-all.sh` | 主控脚本 |
| `01-create-spaces.sh` | 批量创建 Shared Spaces |
| `verify.sh` | 验证配置 |
| `cleanup.sh` | 清理所有 Spaces（危险！） |

## Space 成员权限

成员访问权限通过 IAM Policy 控制（在 `01-iam` 中配置）：

- **Owner**: 完全控制（创建、删除、管理）
- **Members**: 读写（使用 Notebook、上传文件）

## 标签设计

每个 Space 包含以下标签：

| Tag Key | 说明 | 示例 |
|---------|------|------|
| Team | 团队全称 | risk-control |
| Project | 项目名称 | fraud-detection |
| Owner | 所有者 Profile | profile-rc-alice |
| Environment | 环境 | production |
| ManagedBy | 管理标识 | acme-sagemaker |

## 输出文件

```
output/
└── spaces.csv    # Space 清单
```

CSV 格式：
```csv
space_name,team,project,owner_profile,members
space-rc-fraud-detection,risk-control,fraud-detection,profile-rc-alice,profile-rc-bob;profile-rc-carol
```

## 验证命令

```bash
# 列出所有 Spaces
aws sagemaker list-spaces --domain-id d-xxxxxxxxx

# 查看单个 Space 详情
aws sagemaker describe-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-fraud-detection
```

## 协作最佳实践

| 实践 | 说明 |
|------|------|
| 命名规范 | `{日期}_{作者}_{主题}.ipynb` |
| 版本控制 | 定期推送到 CodeCommit |
| 数据存储 | 大数据存 S3，不存 Space EBS |
| 避免冲突 | 编辑前通知团队成员 |

## 清理

⚠️ **警告**: 清理将删除 Space 中的所有数据！

```bash
# 需要手动输入 DELETE 确认
./cleanup.sh

# 跳过确认（危险！）
./cleanup.sh --force
```

## 完成后

所有脚本执行完成后，平台搭建完成！

用户登录流程：
1. IAM User 登录 AWS Console
2. 导航到 SageMaker → Studio
3. 选择自己的 User Profile
4. 点击 "Open Studio"
5. 在 Studio 中访问项目的 Shared Space

## 参考文档

- [07-Shared Space 设计](../../docs/07-shared-space.md)
- [08-实施步骤指南](../../docs/08-implementation-guide.md)

