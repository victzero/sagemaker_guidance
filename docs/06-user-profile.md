# 06 - User Profile 设计

> 本文档描述 SageMaker User Profile 的设计和配置

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符         | 说明                    | 示例值                   |
| -------------- | ----------------------- | ------------------------ |
| `{account-id}` | AWS 账号 ID             | `123456789012`           |
| `{team}`       | 团队缩写                | `rc`、`algo`             |
| `{project}`    | 项目名称                | `project-a`、`project-x` |
| `{name}`       | 用户名                  | `alice`、`frank`         |
| `{iam-user}`   | IAM 用户名              | `sm-rc-alice`            |
| `d-xxxxxxxxx`  | Domain ID（创建后获取） | `d-abc123def456`         |
| `sg-xxxxxxxxx` | 安全组 ID               | `sg-0abc123def456`       |

---

## 1. User Profile 概述

### 1.1 什么是 User Profile

User Profile 是 SageMaker Domain 中代表用户在特定项目中的配置实体：

- 每个 IAM User 在每个参与的项目中有**独立的 User Profile**
- 定义用户在该项目中的 Execution Role
- 定义用户的默认设置
- 关联用户的 Home 目录（EFS）
- 配套一个 **Private Space** 用于运行 JupyterLab

### 1.2 设计原则

| 原则         | 说明                                              |
| ------------ | ------------------------------------------------- |
| **一对多映射** | 每个 IAM User 可对应多个 Profile（每项目一个）  |
| 命名一致     | User Profile 名称包含团队、项目、用户信息         |
| 项目隔离     | 通过 Profile 绑定项目级 Execution Role，实现数据隔离 |
| Private Space | 每个 Profile 配套一个 Private Space              |

### 1.3 架构图

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

---

## 2. User Profile 规划

### 2.1 User Profile 清单

| User Profile             | Private Space            | IAM User      | 项目            | Execution Role                              |
| ------------------------ | ------------------------ | ------------- | --------------- | ------------------------------------------- |
| profile-rc-fraud-alice   | space-rc-fraud-alice     | sm-rc-alice   | fraud-detection | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| profile-rc-fraud-bob     | space-rc-fraud-bob       | sm-rc-bob     | fraud-detection | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| profile-rc-aml-alice     | space-rc-aml-alice       | sm-rc-alice   | anti-money-laundering | SageMaker-RiskControl-AML-ExecutionRole    |
| profile-rc-aml-charlie   | space-rc-aml-charlie     | sm-rc-charlie | anti-money-laundering | SageMaker-RiskControl-AML-ExecutionRole    |
| profile-algo-rec-david   | space-algo-rec-david     | sm-algo-david | recommendation  | SageMaker-Algorithm-Recommendation-ExecutionRole |
| profile-algo-rec-eve     | space-algo-rec-eve       | sm-algo-eve   | recommendation  | SageMaker-Algorithm-Recommendation-ExecutionRole |

> **注意**: Alice 参与了两个项目（fraud-detection 和 anti-money-laundering），所以有两个独立的 Profile。

### 2.2 命名规范

```
User Profile:  profile-{team}-{project_short}-{user}
Private Space: space-{team}-{project_short}-{user}
IAM User:      sm-{team}-{name}

其中 project_short 是项目名的第一部分:
  fraud-detection → fraud
  anti-money-laundering → anti (或 aml)
  recommendation → rec

示例:
- profile-rc-fraud-alice + space-rc-fraud-alice  ↔  sm-rc-alice (fraud-detection 项目)
- profile-rc-aml-alice   + space-rc-aml-alice    ↔  sm-rc-alice (anti-money-laundering 项目)
- profile-algo-rec-david + space-algo-rec-david  ↔  sm-algo-david (recommendation 项目)
```

### 2.3 资源命名对照表

| 资源类型        | 命名格式                                    | 示例                                             |
| --------------- | ------------------------------------------- | ------------------------------------------------ |
| IAM User        | `sm-{team}-{user}`                          | `sm-rc-alice`                                    |
| User Profile    | `profile-{team}-{project_short}-{user}`     | `profile-rc-fraud-alice`                         |
| Private Space   | `space-{team}-{project_short}-{user}`       | `space-rc-fraud-alice`                           |
| Execution Role  | `SageMaker-{Team}-{Project}-ExecutionRole`  | `SageMaker-RiskControl-FraudDetection-ExecutionRole` |
| S3 Bucket       | `{company}-sm-{team}-{project}`             | `acme-sm-rc-fraud-detection`                     |

---

## 3. User Profile 配置

### 3.1 核心配置

| 配置项          | 说明         | 示例                                                |
| --------------- | ------------ | --------------------------------------------------- |
| UserProfileName | Profile 名称 | `profile-rc-fraud-alice`                            |
| DomainId        | 所属 Domain  | `d-xxxxxxxxx`                                       |
| ExecutionRole   | 执行角色     | `SageMaker-RiskControl-FraudDetection-ExecutionRole`|

### 3.2 用户设置 (UserSettings)

| 配置项            | 推荐值                  | 说明                         |
| ----------------- | ----------------------- | ---------------------------- |
| ExecutionRole     | 项目级 Role             | 每用户按项目分配             |
| SecurityGroups    | [`{TAG_PREFIX}-studio`] | 继承 Domain                  |
| DefaultLandingUri | studio::                | 默认打开 Studio              |

### 3.3 JupyterLab 设置

| 配置项                                      | 推荐值       | 说明               |
| ------------------------------------------- | ------------ | ------------------ |
| DefaultResourceSpec.InstanceType            | ml.t3.medium | 默认实例           |
| AppLifecycleManagement.IdleSettings         | 继承 Domain  | 内置 Idle Shutdown |

---

## 3A. Private Space 配置

### 3A.1 什么是 Private Space

Private Space 是用户的私有工作空间，每个 User Profile 配套一个：

- **继承 Execution Role**：自动继承 User Profile 的 Execution Role
- **数据隔离**：只有 Profile 所有者可以访问
- **项目级 S3 访问**：可以访问项目 S3 桶

### 3A.2 Private vs Shared Space

| 特性           | Private Space         | Shared Space           |
| -------------- | --------------------- | ---------------------- |
| **所有者**     | 单个用户              | 多用户共享             |
| **Execution Role** | 继承 User Profile | 继承 Domain Default    |
| **项目 S3 访问** | ✅ 有权限           | ❌ 无权限              |
| **数据隔离**   | ✅ 完全隔离          | ⚠️ 共享                |
| **用途**       | 项目开发             | 团队协作、演示         |

> **本项目使用 Private Space** 以实现项目级数据隔离。

### 3A.3 Space 配置

| 配置项                    | 值                          | 说明                    |
| ------------------------- | --------------------------- | ----------------------- |
| SpaceName                 | `space-{team}-{project}-{user}` | 与 Profile 对应     |
| SharingType               | `Private`                   | 私有空间                |
| OwnerUserProfileName      | Profile 名称                | 绑定所有者              |
| SpaceStorageSettings.EBS  | 50 GB                       | 默认 EBS 大小           |
| AppType                   | JupyterLab                  | 应用类型                |

---

## 4. User Profile 与 IAM User 绑定

### 4.1 绑定机制（IAM 模式）

在 IAM 认证模式下，一个用户可能有多个 Profile（每项目一个），需要可验证的权限约束：

- **命名约定**：`profile-rc-fraud-alice` ↔ `sm-rc-alice` (fraud-detection 项目)
- **资源标记**：给 User Profile 打上 `Owner=sm-rc-alice`、`Team`、`Project` 等标签
- **访问强制**：通过 IAM Policy 限制：
  - 只允许用户对"自己的 User Profile"执行 `DescribeUserProfile`、`CreatePresignedDomainUrl`
  - 只允许用户在"所属项目 Space"执行 `CreateApp/UpdateApp/DeleteApp`

> 关键点：即使 Console 能"看到"其他 Profile，用户也必须**无法打开**（即无法生成 Presigned URL / 无法创建 App），从而在验收层面可证明。

### 4.2 访问控制

IAM User 只能访问与自己绑定的 User Profile（可能多个）：

```
sm-rc-alice 登录后（参与 fraud-detection 和 aml 两个项目）:
✅ 可以访问: profile-rc-fraud-alice (fraud-detection 项目)
✅ 可以访问: profile-rc-aml-alice   (anti-money-laundering 项目)
❌ 不能访问: profile-rc-fraud-bob   (他人的 Profile)
❌ 不能访问: profile-algo-rec-david (其他团队项目)
```

### 4.3 可验证方案（验收用例）

建议用以下用例作为"可验收"的定义（通过 Console 或 CLI 均可验证）：

- **用例 A：打开自己的 Profile + Space**
  - 预期：成功进入 Studio；可启动对应的 Private Space。
- **用例 B：打开他人的 Profile**
  - 预期：失败（AccessDenied 或无法进入 Studio）。
- **用例 C：访问他人的 Private Space**
  - 预期：失败（AccessDenied）。
- **用例 D：在 Profile A 中访问项目 B 的 S3 桶**
  - 预期：失败（AccessDenied）— 验证项目隔离。

### 4.4 IAM Policy 配置

IAM User 需要以下权限访问自己的 User Profile：

```
权限要点:
1. sagemaker:DescribeUserProfile - 查看 Profile
2. sagemaker:CreatePresignedDomainUrl - 生成登录 URL
3. sagemaker:CreateApp - 创建应用
4. sagemaker:DeleteApp - 删除应用
5. sagemaker:DescribeSpace - 查看 Space
6. sagemaker:CreateSpace - 创建 Space（如未预创建）

条件限制:
- Resource: 只能是自己的 UserProfile ARN 和 Space ARN
- 或使用 Tags 限制（Owner=sm-{team}-{user}）
```

---

## 5. Execution Role 绑定

### 5.1 绑定策略

**策略**：同一项目的用户使用相同的 Execution Role，不同项目使用不同 Role

```
fraud-detection 项目（风控团队）:
├── profile-rc-fraud-alice  → SageMaker-RiskControl-FraudDetection-ExecutionRole
├── profile-rc-fraud-bob    → SageMaker-RiskControl-FraudDetection-ExecutionRole
└── profile-rc-fraud-carol  → SageMaker-RiskControl-FraudDetection-ExecutionRole

anti-money-laundering 项目（风控团队）:
├── profile-rc-aml-alice    → SageMaker-RiskControl-AML-ExecutionRole
└── profile-rc-aml-charlie  → SageMaker-RiskControl-AML-ExecutionRole

recommendation 项目（算法团队）:
├── profile-algo-rec-david  → SageMaker-Algorithm-Recommendation-ExecutionRole
└── profile-algo-rec-eve    → SageMaker-Algorithm-Recommendation-ExecutionRole
```

> **注意**: Alice 参与两个项目，所以有两个 Profile，分别绑定不同的 Execution Role。

### 5.2 权限效果

用户在 Private Space 中执行代码时：

- **Space 自动继承 User Profile 的 Execution Role**
- 该 Role 决定了可访问的 S3 Bucket（仅限所属项目）
- 该 Role 决定了可使用的 AWS 服务

```
sm-rc-alice 登录 profile-rc-fraud-alice:
  → 进入 space-rc-fraud-alice
  → 使用 SageMaker-RiskControl-FraudDetection-ExecutionRole
  → ✅ 可访问 acme-sm-rc-fraud-detection S3 桶
  → ❌ 无法访问 acme-sm-rc-aml S3 桶（不同项目）

sm-rc-alice 登录 profile-rc-aml-alice:
  → 进入 space-rc-aml-alice
  → 使用 SageMaker-RiskControl-AML-ExecutionRole
  → ✅ 可访问 acme-sm-rc-aml S3 桶
  → ❌ 无法访问 acme-sm-rc-fraud-detection S3 桶
```

---

## 6. 标签设计

### 6.1 User Profile 必需标签

| Tag Key     | Tag Value            | 示例                 |
| ----------- | -------------------- | -------------------- |
| Team        | {team_fullname}      | `risk-control`       |
| Project     | {project}            | `fraud-detection`    |
| Owner       | {iam-user}           | `sm-rc-alice`        |
| Environment | production           | `production`         |
| ManagedBy   | {TAG_PREFIX}         | `acme-sagemaker`     |

### 6.2 Private Space 必需标签

| Tag Key     | Tag Value            | 示例                 |
| ----------- | -------------------- | -------------------- |
| Team        | {team_fullname}      | `risk-control`       |
| Project     | {project}            | `fraud-detection`    |
| Owner       | {user_name}          | `alice`              |
| SpaceType   | private              | `private`            |
| Environment | production           | `production`         |
| ManagedBy   | {TAG_PREFIX}         | `acme-sagemaker`     |

### 6.3 标签用途

标签可用于：

1. **权限控制**：IAM Policy 中的 Condition（限制用户只能访问自己的资源）
2. **成本分配**：Cost Explorer 按 Team/Project 分析成本
3. **资源查找**：按标签筛选 Profile 和 Space
4. **ABAC 访问控制**：基于属性的访问控制（按 Owner 标签限制）

---

## 7. Home 目录管理

### 7.1 EFS Home 目录

每个 User Profile 在 EFS 上有独立的 Home 目录：

```
EFS 结构:
/
├── {user-profile-id-1}/     # Alice 的 Home
│   ├── notebooks/
│   ├── data/
│   └── .config/
├── {user-profile-id-2}/     # Bob 的 Home
│   ├── notebooks/
│   └── data/
└── ...
```

### 7.2 数据隔离

| 访问类型     | 权限          |
| ------------ | ------------- |
| 自己的 Home  | 读写          |
| 他人的 Home  | 无权限        |
| Shared Space | 按 Space 配置 |

### 7.3 Home 目录定位与数据管理规范

> ⚠️ **重要**：EFS Home 目录应视为**易失性工作区**，不承诺长期持久化或跨项目迁移。

| 数据类型     | 推荐存储位置         | 说明                                  |
| ------------ | -------------------- | ------------------------------------- |
| **代码**     | AWS CodeCommit / Git | 建议入版本控制，不建议仅存 Home 目录  |
| **数据集**   | S3 Bucket            | 项目数据统一存 S3，便于共享和权限管理 |
| **模型产物** | S3 Bucket            | 训练输出、模型文件存 S3               |
| **临时文件** | EFS Home             | 仅用于开发调试的临时文件              |
| **个人配置** | EFS Home             | IDE 配置、环境变量等                  |

**数据丢失风险场景**：

- 用户跨项目/团队迁移时，若选择"删除重建 Profile"，Home 目录数据将丢失
- 平台不提供 EFS 数据的自动备份或迁移服务

**最佳实践**：

1. 每日将重要 Notebook 推送到 CodeCommit
2. 处理后的数据及时上传到 S3
3. 将 Home 目录视为"可随时清空"的临时空间

---

## 8. User Profile 创建参数

### 8.1 参数模板

```
UserProfile 配置:
- UserProfileName: profile-{team}-{project_short}-{user}
- DomainId: d-xxxxxxxxx
- Tags:
    - Key: Team, Value: {team_fullname}
    - Key: Project, Value: {project}
    - Key: Owner, Value: sm-{team}-{name}
    - Key: Environment, Value: production
    - Key: ManagedBy, Value: {TAG_PREFIX}
- UserSettings:
    - ExecutionRole: arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole
    - SecurityGroups: [{sg-id}]

Private Space 配置:
- SpaceName: space-{team}-{project_short}-{user}
- SharingType: Private
- OwnerUserProfileName: profile-{team}-{project_short}-{user}
- SpaceStorageSettings.EbsVolumeSizeInGb: 50
- AppType: JupyterLab
```

### 8.2 批量创建示例

| #   | UserProfileName          | Private Space            | IAM User      | Execution Role                              |
| --- | ------------------------ | ------------------------ | ------------- | ------------------------------------------- |
| 1   | profile-rc-fraud-alice   | space-rc-fraud-alice     | sm-rc-alice   | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| 2   | profile-rc-fraud-bob     | space-rc-fraud-bob       | sm-rc-bob     | SageMaker-RiskControl-FraudDetection-ExecutionRole |
| 3   | profile-rc-aml-alice     | space-rc-aml-alice       | sm-rc-alice   | SageMaker-RiskControl-AML-ExecutionRole     |
| 4   | profile-algo-rec-david   | space-algo-rec-david     | sm-algo-david | SageMaker-Algorithm-Recommendation-ExecutionRole |

---

## 9. 用户迁移/变更

### 9.1 用户换项目

当用户从项目 A 调到项目 B 时：

```
方案 1: 修改现有 Profile（推荐）
- 更新 Execution Role
- 更新 Tags
- 用户保留 Home 目录数据

方案 2: 删除重建
- 删除旧 Profile
- 创建新 Profile
- Home 目录数据会丢失
```

### 9.2 用户离职

```
1. 删除 User Profile
2. 禁用 IAM User
3. （可选）备份 Home 目录数据
4. 移除 Group 成员资格
```

---

## 10. CLI 创建命令

### 10.1 创建 User Profile

```bash
# 创建 User Profile
aws sagemaker create-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-fraud-alice \
  --user-settings '{
    "ExecutionRole": "arn:aws:iam::{account-id}:role/SageMaker-RiskControl-FraudDetection-ExecutionRole",
    "SecurityGroups": ["{sg-id}"]
  }' \
  --tags \
    Key=Team,Value=risk-control \
    Key=Project,Value=fraud-detection \
    Key=Owner,Value=sm-rc-alice \
    Key=Environment,Value=production \
    Key=ManagedBy,Value=acme-sagemaker
```

### 10.2 创建 Private Space

```bash
# 创建 Private Space（绑定到 User Profile）
aws sagemaker create-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-fraud-alice \
  --space-sharing-settings '{"SharingType": "Private"}' \
  --ownership-settings '{"OwnerUserProfileName": "profile-rc-fraud-alice"}' \
  --space-settings '{
    "AppType": "JupyterLab",
    "SpaceStorageSettings": {
      "EbsStorageSettings": {
        "EbsVolumeSizeInGb": 50
      }
    }
  }' \
  --tags \
    Key=Team,Value=risk-control \
    Key=Project,Value=fraud-detection \
    Key=Owner,Value=alice \
    Key=SpaceType,Value=private \
    Key=Environment,Value=production \
    Key=ManagedBy,Value=acme-sagemaker
```

### 10.3 查询 User Profile 和 Space

```bash
# 列出 Domain 下所有 User Profiles
aws sagemaker list-user-profiles --domain-id d-xxxxxxxxx

# 列出 Domain 下所有 Spaces
aws sagemaker list-spaces --domain-id d-xxxxxxxxx

# 查看 Profile 详情
aws sagemaker describe-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-fraud-alice

# 查看 Space 详情
aws sagemaker describe-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-fraud-alice
```

### 10.4 删除 User Profile 和 Space

```bash
# 1. 先删除 Space 中的 Apps
aws sagemaker list-apps \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-fraud-alice

# 删除每个 App（如有）
aws sagemaker delete-app \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-fraud-alice \
  --app-type JupyterLab \
  --app-name default

# 2. 等待后删除 Space
aws sagemaker delete-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-fraud-alice

# 3. 最后删除 Profile
aws sagemaker delete-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-fraud-alice
```

---

## 11. Idle Shutdown 配置

> 📌 **推荐方案**：使用 SageMaker 内置 Idle Shutdown 功能，在 Domain 级别配置，所有 User Profile 自动继承。详见 [05-sagemaker-domain.md § 11](05-sagemaker-domain.md#11-idle-shutdown-配置内置功能)。

### Profile 级别继承

User Profile 自动继承 Domain 的 Idle Shutdown 配置：

```
Domain DefaultUserSettings:
  JupyterLabAppSettings:
    AppLifecycleManagement:
      IdleSettings:
        LifecycleManagement: ENABLED
        IdleTimeoutInMinutes: 60

↓ 所有 User Profile 继承 ↓

profile-rc-fraud-alice → 60 分钟空闲自动关机
profile-rc-fraud-bob   → 60 分钟空闲自动关机
...
```

### 自定义配置（不推荐）

除非有特殊需求，否则不建议为单个 Profile 配置不同的 Idle Shutdown 设置。

---

## 12. 批量创建脚本

### 12.1 用户配置文件 `users.csv`

```csv
profile_name,space_name,iam_user,team,project,execution_role
profile-rc-fraud-alice,space-rc-fraud-alice,sm-rc-alice,risk-control,fraud-detection,SageMaker-RiskControl-FraudDetection-ExecutionRole
profile-rc-fraud-bob,space-rc-fraud-bob,sm-rc-bob,risk-control,fraud-detection,SageMaker-RiskControl-FraudDetection-ExecutionRole
profile-rc-aml-alice,space-rc-aml-alice,sm-rc-alice,risk-control,anti-money-laundering,SageMaker-RiskControl-AML-ExecutionRole
profile-rc-aml-charlie,space-rc-aml-charlie,sm-rc-charlie,risk-control,anti-money-laundering,SageMaker-RiskControl-AML-ExecutionRole
profile-algo-rec-david,space-algo-rec-david,sm-algo-david,algorithm,recommendation,SageMaker-Algorithm-Recommendation-ExecutionRole
profile-algo-rec-eve,space-algo-rec-eve,sm-algo-eve,algorithm,recommendation,SageMaker-Algorithm-Recommendation-ExecutionRole
```

> **注意**: Alice 参与两个项目，所以有两行配置（fraud-detection 和 anti-money-laundering）。

### 12.2 批量创建脚本 `create-profiles-and-spaces.sh`

```bash
#!/bin/bash
# create-profiles-and-spaces.sh - 批量创建 User Profiles 和 Private Spaces
# 用法: ./create-profiles-and-spaces.sh <domain-id> <account-id> <users.csv>

set -e

DOMAIN_ID="${1:?Usage: $0 <domain-id> <account-id> <users.csv>}"
ACCOUNT_ID="${2:?Usage: $0 <domain-id> <account-id> <users.csv>}"
USERS_FILE="${3:?Usage: $0 <domain-id> <account-id> <users.csv>}"
SECURITY_GROUP="${SG_ID:-sg-sagemaker-studio}"  # 从环境变量或默认值
TAG_PREFIX="${TAG_PREFIX:-acme-sagemaker}"
DEFAULT_EBS_SIZE="${DEFAULT_EBS_SIZE:-50}"

# 跳过 CSV 头行
tail -n +2 "$USERS_FILE" | while IFS=',' read -r profile_name space_name iam_user team project execution_role; do
    echo "=========================================="
    echo "Processing: $profile_name"

    # 提取用户名（从 iam_user 如 sm-rc-alice 提取 alice）
    user_name=$(echo "$iam_user" | sed 's/sm-[^-]*-//')

    # 1. 创建 User Profile
    if aws sagemaker describe-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$profile_name" >/dev/null 2>&1; then
        echo "  [Profile] Already exists, skipping."
    else
        echo "  [Profile] Creating..."
        aws sagemaker create-user-profile \
            --domain-id "$DOMAIN_ID" \
            --user-profile-name "$profile_name" \
            --user-settings "{
                \"ExecutionRole\": \"arn:aws:iam::${ACCOUNT_ID}:role/${execution_role}\",
                \"SecurityGroups\": [\"${SECURITY_GROUP}\"]
            }" \
            --tags \
                Key=Team,Value="$team" \
                Key=Project,Value="$project" \
                Key=Owner,Value="$iam_user" \
                Key=Environment,Value=production \
                Key=ManagedBy,Value="$TAG_PREFIX"
        echo "  [Profile] Created."
        sleep 2  # 等待 Profile 就绪
    fi

    # 2. 创建 Private Space
    if aws sagemaker describe-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" >/dev/null 2>&1; then
        echo "  [Space] Already exists, skipping."
    else
        echo "  [Space] Creating..."
        aws sagemaker create-space \
            --domain-id "$DOMAIN_ID" \
            --space-name "$space_name" \
            --space-sharing-settings '{"SharingType": "Private"}' \
            --ownership-settings "{\"OwnerUserProfileName\": \"${profile_name}\"}" \
            --space-settings "{
                \"AppType\": \"JupyterLab\",
                \"SpaceStorageSettings\": {
                    \"EbsStorageSettings\": {
                        \"EbsVolumeSizeInGb\": ${DEFAULT_EBS_SIZE}
                    }
                }
            }" \
            --tags \
                Key=Team,Value="$team" \
                Key=Project,Value="$project" \
                Key=Owner,Value="$user_name" \
                Key=SpaceType,Value=private \
                Key=Environment,Value=production \
                Key=ManagedBy,Value="$TAG_PREFIX"
        echo "  [Space] Created."
    fi

    sleep 1  # 避免 API 限流
done

echo ""
echo "=========================================="
echo "Batch creation completed. Verifying..."
echo ""
echo "User Profiles:"
aws sagemaker list-user-profiles --domain-id "$DOMAIN_ID" \
    --query 'UserProfiles[].UserProfileName' --output table
echo ""
echo "Private Spaces:"
aws sagemaker list-spaces --domain-id "$DOMAIN_ID" \
    --query 'Spaces[?SpaceSharingSettings.SharingType==`Private`].SpaceName' --output table
```

### 12.3 执行批量创建

```bash
# 添加执行权限
chmod +x create-user-profiles.sh

# 执行（替换实际值）
./create-user-profiles.sh d-xxxxxxxxx 123456789012 users.csv
```

### 12.4 批量删除脚本（清理用）

```bash
#!/bin/bash
# delete-user-profiles.sh - 批量删除 User Profiles（慎用）
# 用法: ./delete-user-profiles.sh <domain-id> <users.csv>

set -e

DOMAIN_ID="${1:?Usage: $0 <domain-id> <users.csv>}"
USERS_FILE="${2:?Usage: $0 <domain-id> <users.csv>}"

echo "⚠️  WARNING: This will delete User Profiles and their Home directories!"
read -p "Type 'DELETE' to confirm: " confirm
[ "$confirm" != "DELETE" ] && echo "Aborted." && exit 1

tail -n +2 "$USERS_FILE" | while IFS=',' read -r profile_name _; do
    echo "Deleting: $profile_name"

    # 先删除所有 Apps
    APPS=$(aws sagemaker list-apps --domain-id "$DOMAIN_ID" --user-profile-name "$profile_name" \
        --query 'Apps[?Status!=`Deleted`].[AppType,AppName]' --output text 2>/dev/null || true)

    if [ -n "$APPS" ]; then
        echo "$APPS" | while read -r app_type app_name; do
            echo "  Deleting App: $app_type/$app_name"
            aws sagemaker delete-app \
                --domain-id "$DOMAIN_ID" \
                --user-profile-name "$profile_name" \
                --app-type "$app_type" \
                --app-name "$app_name" 2>/dev/null || true
        done
        echo "  Waiting for Apps to be deleted..."
        sleep 30
    fi

    # 删除 Profile
    aws sagemaker delete-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$profile_name" 2>/dev/null || true

    echo "  → Deleted."
    sleep 1
done

echo "Batch deletion completed."
```

---

## 13. 用户自助服务门户（可选）

> 📌 此功能为可选的高级配置，适用于需要"用户自助申请 Profile"的大规模场景。

### 13.1 方案概述

| 方案                     | 复杂度 | 说明                                       |
| ------------------------ | ------ | ------------------------------------------ |
| **ServiceNow 集成**      | 高     | 企业 ITSM 集成，适合已有 ServiceNow 的组织 |
| **API Gateway + Lambda** | 中     | 自建审批流程，Lambda 调用 SageMaker API    |
| **Step Functions**       | 中     | 编排审批工作流                             |
| **手工 + Jira**          | 低     | 通过 Jira Ticket 触发管理员手动创建        |

### 13.2 简易自助流程（API Gateway + Lambda）

```
用户提交申请（表单）
    │
    ▼
API Gateway → Lambda（验证 + 记录）
    │
    ▼
SNS 通知 → 管理员审批
    │
    ▼
管理员点击审批链接
    │
    ▼
Lambda 调用 create-user-profile
    │
    ▼
通知用户创建完成
```

### 13.3 建议

对于 12-18 人规模的 ML 平台：

- **推荐**：手工创建 + 批量脚本（本文档 § 12）
- **不推荐**：过度投入自助门户开发

自助门户适用于：

- 用户规模 > 50 人
- 高频的用户增减（每周多次）
- 已有成熟的 IAM 自助体系可复用

---

## 14. 检查清单

### 创建前

- [ ] Domain 已创建且状态为 InService
- [ ] IAM Users 已创建
- [ ] Execution Roles 已创建（项目级，4 角色设计）
- [ ] 确认用户-项目对应关系（一个用户可参与多个项目）

### 创建时

- [ ] User Profile 命名符合规范 (`profile-{team}-{project}-{user}`)
- [ ] Private Space 命名符合规范 (`space-{team}-{project}-{user}`)
- [ ] 绑定正确的项目 Execution Role
- [ ] Space 的 OwnerUserProfileName 正确指向 Profile
- [ ] 添加必需的标签（Team, Project, Owner, SpaceType）

### 创建后

- [ ] 验证 User Profile 状态为 InService
- [ ] 验证 Private Space 状态为 InService
- [ ] 验证用户可以登录对应 Profile
- [ ] 验证 Space 继承了正确的 Execution Role
- [ ] 验证 S3 访问权限（只能访问项目 Bucket）
- [ ] 验证跨项目访问被拒绝（AccessDenied）

---

## 15. 实现脚本

User Profile 和 Private Space 由自动化脚本创建，详见 [scripts/05-user-profiles/README.md](../scripts/05-user-profiles/README.md)。

### 脚本清单

| 脚本                      | 用途                              |
| ------------------------- | --------------------------------- |
| `00-init.sh`              | 初始化和环境变量验证              |
| `01-create-profiles.sh`   | 批量创建 User Profiles            |
| `02-create-spaces.sh`     | 批量创建 Private Spaces           |
| `check.sh`                | 前置检查（Domain、Role 存在）     |
| `verify.sh`               | 验证 Profile 和 Space 状态        |
| `setup-all.sh`            | 一次性创建所有 Profile + Space    |
| `cleanup.sh`              | 清理资源（⚠️ 危险）               |

### 关键函数

```bash
# 创建单个 Profile + Space
create_user_profile_and_space() {
  local team=$1
  local project=$2
  local user=$3

  local profile_name="profile-${team}-${project}-${user}"
  local space_name="space-${team}-${project}-${user}"

  # 1. 创建 Profile
  aws sagemaker create-user-profile ...

  # 2. 等待 Profile Ready
  wait_for_profile "${profile_name}"

  # 3. 创建 Private Space
  aws sagemaker create-space ...

  # 4. 等待 Space Ready
  wait_for_space "${space_name}"
}
```

### 环境变量

| 变量               | 说明                           |
| ------------------ | ------------------------------ |
| `DOMAIN_ID`        | SageMaker Domain ID            |
| `DEFAULT_EBS_SIZE` | Private Space EBS 大小 (默认 50GB) |
| `TAG_PREFIX`       | 资源标签前缀                   |

### 输出文件

```
output/
└── profiles.csv    # Profile 和 Space 清单
```
