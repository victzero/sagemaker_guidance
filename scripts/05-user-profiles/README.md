# 05 - User Profiles 脚本

为每个 IAM 用户创建对应的 SageMaker User Profile。

## 前置条件

1. 已完成 `01-iam/` IAM 用户和 Execution Roles 创建
2. 已完成 `04-sagemaker-domain/` Domain 创建
3. 已配置 `.env.shared` 中的用户信息

## 快速开始

```bash
# 一键执行
./setup-all.sh

# 验证
./verify.sh
```

## 创建的资源

根据 `.env.shared` 中配置的用户自动生成：

| User Profile | IAM User | 团队 | 项目 | Execution Role |
|--------------|----------|------|------|----------------|
| profile-rc-alice | sm-rc-alice | 风控 | fraud-detection | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| profile-rc-bob | sm-rc-bob | 风控 | fraud-detection | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| ... | ... | ... | ... | ... |

## 命名规范

```
User Profile: profile-{team}-{name}
IAM User:     sm-{team}-{name}

映射关系:
  profile-rc-alice  ←→  sm-rc-alice
  profile-algo-frank  ←→  sm-algo-frank
```

## 脚本说明

| 脚本 | 功能 |
|------|------|
| `setup-all.sh` | 主控脚本 |
| `01-create-user-profiles.sh` | 批量创建 User Profiles |
| `verify.sh` | 验证配置 |
| `cleanup.sh` | 清理所有 User Profiles（危险！） |

## 标签设计

每个 User Profile 包含以下标签：

| Tag Key | 说明 | 示例 |
|---------|------|------|
| Team | 团队全称 | risk-control |
| Project | 项目名称 | fraud-detection |
| Owner | 对应 IAM 用户 | sm-rc-alice |
| Environment | 环境 | production |
| ManagedBy | 管理标识 | acme-sagemaker |

## 输出文件

```
output/
└── user-profiles.csv    # Profile 清单
```

CSV 格式：
```csv
profile_name,iam_user,team,project,execution_role
profile-rc-alice,sm-rc-alice,risk-control,fraud-detection,SageMaker-RiskControl-FraudDetection-ExecutionRole
```

## 验证命令

```bash
# 列出所有 User Profiles
aws sagemaker list-user-profiles --domain-id d-xxxxxxxxx

# 查看单个 Profile 详情
aws sagemaker describe-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-alice
```

## 清理

⚠️ **警告**: 清理将删除用户的 EFS Home 目录数据！

```bash
# 需要手动输入 DELETE 确认
./cleanup.sh

# 跳过确认（危险！）
./cleanup.sh --force
```

## 下一步

1. 创建 Shared Spaces: `cd ../06-spaces && ./setup-all.sh`
2. 分发用户凭证（见 `01-iam/output/user-credentials.txt`）

## 参考文档

- [06-User Profile 设计](../../docs/06-user-profile.md)
- [08-实施步骤指南](../../docs/08-implementation-guide.md)

