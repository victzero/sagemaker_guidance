# 05 - User Profiles 脚本

为每个用户在每个参与的项目中创建独立的 SageMaker User Profile。

## 设计说明

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    User Profile 架构                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  一个用户可以参与多个项目，每个项目有独立的 Profile:                    │
│                                                                         │
│  IAM User: sm-rc-alice                                                  │
│      │                                                                  │
│      ├── profile-rc-fraud-alice  → Fraud Execution Role                │
│      │       └── Private Space → S3: fraud-detection/*                 │
│      │                                                                  │
│      └── profile-rc-aml-alice    → AML Execution Role                  │
│              └── Private Space → S3: anti-money-laundering/*           │
│                                                                         │
│  用户登录 Studio 时选择对应项目的 Profile                               │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

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

## 命名规范

```
命名格式: profile-{team}-{project}-{user}

示例:
├── profile-rc-fraud-alice      # RC 团队 / Fraud Detection / Alice
├── profile-rc-fraud-bob        # RC 团队 / Fraud Detection / Bob
├── profile-rc-aml-alice        # RC 团队 / AML / Alice (同一用户不同项目)
├── profile-rc-aml-charlie      # RC 团队 / AML / Charlie
├── profile-algo-rec-david      # Algorithm 团队 / Recommendation / David
└── profile-algo-rec-eve        # Algorithm 团队 / Recommendation / Eve
```

## 创建的资源

根据 `.env.shared` 中配置的用户自动生成：

| User Profile | IAM User | 团队 | 项目 | Execution Role |
|--------------|----------|------|------|----------------|
| profile-rc-fraud-alice | sm-rc-alice | 风控 | fraud-detection | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| profile-rc-fraud-bob | sm-rc-bob | 风控 | fraud-detection | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| profile-rc-aml-alice | sm-rc-alice | 风控 | anti-money-laundering | SageMaker-RiskControl-AML-ExecutionRole |
| ... | ... | ... | ... | ... |

**Profile 数量** = Σ (每个项目的用户数)

## 资源命名对照表

| 资源类型 | 命名格式 | 示例 |
|----------|----------|------|
| IAM User | `sm-{team}-{user}` | `sm-rc-alice` |
| **User Profile** | `profile-{team}-{project}-{user}` | `profile-rc-fraud-alice` |
| Execution Role | `SageMaker-{Team}-{Project}-ExecutionRole` | `SageMaker-RiskControl-FraudDetection-ExecutionRole` |
| S3 Bucket | `{company}-sm-{team}-{project}` | `acme-sm-rc-fraud-detection` |

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
profile-rc-fraud-alice,sm-rc-alice,risk-control,fraud-detection,SageMaker-RiskControl-FraudDetection-ExecutionRole
profile-rc-aml-alice,sm-rc-alice,risk-control,anti-money-laundering,SageMaker-RiskControl-AML-ExecutionRole
```

## 验证命令

```bash
# 列出所有 User Profiles
aws sagemaker list-user-profiles --domain-id d-xxxxxxxxx

# 查看单个 Profile 详情
aws sagemaker describe-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-fraud-alice
```

## 清理

⚠️ **警告**: 清理将删除用户的 EFS Home 目录数据！

```bash
# 需要手动输入 DELETE 确认
./cleanup.sh

# 跳过确认（危险！）
./cleanup.sh --force
```

## 用户使用流程

1. 用户登录 AWS Console 或获取预签名 URL
2. 访问 SageMaker Studio
3. **选择对应项目的 User Profile**（如 `profile-rc-fraud-alice`）
4. 点击 "Open Studio"
5. 在 Private Space 中进行开发
6. 需要切换项目时，选择另一个 Profile 重新进入

## 常见问题

### Q: 一个用户参与多个项目怎么办？

A: 每个项目创建独立的 Profile，用户需要切换 Profile 来访问不同项目。

```
Alice 参与两个项目:
├── profile-rc-fraud-alice  → 访问 fraud-detection S3
└── profile-rc-aml-alice    → 访问 anti-money-laundering S3
```

### Q: 为什么不用一个 Profile 访问多个项目？

A: 为了**安全隔离**。每个 Profile 绑定单一项目的 Execution Role，确保用户在某个项目的 Space 中只能访问该项目的资源，防止数据泄露。

## 下一步

1. 用户登录 Studio 选择对应项目的 Profile
2. 在 Private Space 中使用 JupyterLab 进行开发
3. 分发用户凭证（见 `01-iam/output/user-credentials.txt`）

## 参考文档

- [06-User Profile 设计](../../docs/06-user-profile.md)
- [08-实施步骤指南](../../docs/08-implementation-guide.md)
