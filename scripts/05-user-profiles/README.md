# 05 - User Profiles & Private Spaces 脚本

为每个用户在每个参与的项目中创建独立的 User Profile 和 Private Space。

## 设计说明

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    User Profile & Private Space 架构                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  一个用户可以参与多个项目，每个项目有独立的 Profile + Space:            │
│                                                                         │
│  IAM User: sm-rc-alice                                                  │
│      │                                                                  │
│      ├── profile-rc-fraud-alice  → Fraud Execution Role                │
│      │       └── space-rc-fraud-alice → Private Space                  │
│      │               └── 可访问: fraud-detection S3 桶                 │
│      │                                                                  │
│      └── profile-rc-aml-alice    → AML Execution Role                  │
│              └── space-rc-aml-alice → Private Space                    │
│                      └── 可访问: anti-money-laundering S3 桶           │
│                                                                         │
│  用户登录 Studio 时选择对应项目的 Profile，进入对应的 Space            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## 前置条件

1. 已完成 `01-iam/` IAM 用户和 Execution Roles 创建
2. 已完成 `04-sagemaker-domain/` Domain 创建
3. 已配置 `.env.shared` 中的用户信息

## 快速开始

```bash
# 一键执行（创建 User Profiles + Private Spaces）
./setup-all.sh

# 验证
./verify.sh
```

## 命名规范

```
命名格式:
  User Profile:  profile-{team}-{project}-{user}
  Private Space: space-{team}-{project}-{user}

示例:
├── profile-rc-fraud-alice  + space-rc-fraud-alice
├── profile-rc-fraud-bob    + space-rc-fraud-bob
├── profile-rc-aml-alice    + space-rc-aml-alice   (同一用户不同项目)
├── profile-rc-aml-charlie  + space-rc-aml-charlie
├── profile-algo-rec-david  + space-algo-rec-david
└── profile-algo-rec-eve    + space-algo-rec-eve
```

## 创建的资源

根据 `.env.shared` 中配置的用户自动生成：

| User Profile | Private Space | IAM User | 项目 | Execution Role |
|--------------|---------------|----------|------|----------------|
| profile-rc-fraud-alice | space-rc-fraud-alice | sm-rc-alice | fraud-detection | RC-FraudDetection-ExecutionRole |
| profile-rc-fraud-bob | space-rc-fraud-bob | sm-rc-bob | fraud-detection | RC-FraudDetection-ExecutionRole |
| profile-rc-aml-alice | space-rc-aml-alice | sm-rc-alice | anti-money-laundering | RC-AML-ExecutionRole |
| ... | ... | ... | ... | ... |

**资源数量** = Σ (每个项目的用户数) × 2 (Profile + Space)

## 资源命名对照表

| 资源类型 | 命名格式 | 示例 |
|----------|----------|------|
| IAM User | `sm-{team}-{user}` | `sm-rc-alice` |
| **User Profile** | `profile-{team}-{project}-{user}` | `profile-rc-fraud-alice` |
| **Private Space** | `space-{team}-{project}-{user}` | `space-rc-fraud-alice` |
| Execution Role | `SageMaker-{Team}-{Project}-ExecutionRole` | `SageMaker-RC-Fraud-ExecutionRole` |
| S3 Bucket | `{company}-sm-{team}-{project}` | `acme-sm-rc-fraud-detection` |

## 脚本说明

| 脚本 | 功能 |
|------|------|
| `setup-all.sh` | 主控脚本（创建 Profiles + Spaces） |
| `01-create-user-profiles.sh` | 批量创建 User Profiles |
| `02-create-private-spaces.sh` | 批量创建 Private Spaces |
| `verify.sh` | 验证配置 |
| `cleanup.sh` | 清理所有资源（危险！） |

## 标签设计

每个资源包含以下标签：

| Tag Key | 说明 | 示例 |
|---------|------|------|
| Team | 团队全称 | risk-control |
| Project | 项目名称 | fraud-detection |
| Owner | 用户名 | alice |
| SpaceType | Space 类型 | private |
| Environment | 环境 | production |
| ManagedBy | 管理标识 | acme-sagemaker |

## 输出文件

```
output/
├── user-profiles.csv    # Profile 清单
└── private-spaces.csv   # Space 清单
```

CSV 格式：
```csv
# user-profiles.csv
profile_name,iam_user,team,project,execution_role
profile-rc-fraud-alice,sm-rc-alice,risk-control,fraud-detection,SageMaker-RC-Fraud-ExecutionRole

# private-spaces.csv
space_name,profile_name,team,project,type
space-rc-fraud-alice,profile-rc-fraud-alice,risk-control,fraud-detection,private
```

## 验证命令

```bash
# 列出所有 User Profiles
aws sagemaker list-user-profiles --domain-id d-xxxxxxxxx

# 列出所有 Spaces
aws sagemaker list-spaces --domain-id d-xxxxxxxxx

# 查看单个 Profile 详情
aws sagemaker describe-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-fraud-alice

# 查看单个 Space 详情
aws sagemaker describe-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-fraud-alice
```

## 清理

⚠️ **警告**: 清理将删除用户的 EFS Home 目录数据！

```bash
# 需要手动输入 DELETE 确认
./cleanup.sh

# 跳过确认（危险！）
./cleanup.sh --force
```

清理顺序：先删除 Spaces，再删除 Profiles。

## 用户使用流程

1. 用户登录 AWS Console 或获取预签名 URL
2. 访问 SageMaker Studio
3. **选择对应项目的 User Profile**（如 `profile-rc-fraud-alice`）
4. 点击 "Open Studio"
5. 选择对应的 Private Space（如 `space-rc-fraud-alice`）
6. 点击 "Run" 启动 JupyterLab
7. 在 JupyterLab 中可以访问项目 S3 桶

## 常见问题

### Q: 一个用户参与多个项目怎么办？

A: 每个项目创建独立的 Profile + Space，用户需要切换 Profile 来访问不同项目。

```
Alice 参与两个项目:
├── profile-rc-fraud-alice + space-rc-fraud-alice → 访问 fraud-detection S3
└── profile-rc-aml-alice   + space-rc-aml-alice   → 访问 anti-money-laundering S3
```

### Q: 为什么不用一个 Profile 访问多个项目？

A: 为了**安全隔离**。每个 Profile 绑定单一项目的 Execution Role，确保用户在某个项目的 Space 中只能访问该项目的资源，防止数据泄露。

### Q: Private Space 和 Shared Space 有什么区别？

A: 
| 特性 | Private Space | Shared Space |
|------|---------------|--------------|
| 所有者 | 单个用户 | 多用户共享 |
| Execution Role | 继承 User Profile | 继承 Domain Default |
| 项目 S3 访问 | ✅ 有权限 | ❌ 无权限 |
| 数据隔离 | ✅ 完全隔离 | ⚠️ 共享 |

本项目使用 Private Space 以实现项目级数据隔离。

## 下一步

1. 用户登录 Studio 选择对应项目的 Profile
2. 选择对应的 Private Space 启动 JupyterLab
3. 分发用户凭证（见 `01-iam/output/user-credentials.txt`）

## 参考文档

- [06-User Profile 设计](../../docs/06-user-profile.md)
- [08-实施步骤指南](../../docs/08-implementation-guide.md)
