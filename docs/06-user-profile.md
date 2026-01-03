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

User Profile 是 SageMaker Domain 中代表单个用户的配置实体：

- 每个 IAM User 对应一个 User Profile
- 定义用户的 Execution Role
- 定义用户的默认设置
- 关联用户的 Home 目录（EFS）

### 1.2 设计原则

| 原则       | 说明                                  |
| ---------- | ------------------------------------- |
| 一对一映射 | 每个 IAM User 对应一个 User Profile   |
| 命名一致   | User Profile 名称与 IAM User 相关联   |
| 角色绑定   | 通过 User Profile 绑定 Execution Role |

---

## 2. User Profile 规划

### 2.1 User Profile 清单

| User Profile       | IAM User      | 团队 | 项目      | Execution Role                        |
| ------------------ | ------------- | ---- | --------- | ------------------------------------- |
| profile-rc-proja-alice   | sm-rc-alice   | 风控 | project-a | SageMaker-RC-ProjectA-ExecutionRole   |
| profile-rc-proja-bob     | sm-rc-bob     | 风控 | project-a | SageMaker-RC-ProjectA-ExecutionRole   |
| profile-rc-proja-carol   | sm-rc-carol   | 风控 | project-a | SageMaker-RC-ProjectA-ExecutionRole   |
| profile-rc-projb-david   | sm-rc-david   | 风控 | project-b | SageMaker-RC-ProjectB-ExecutionRole   |
| profile-rc-projb-emma    | sm-rc-emma    | 风控 | project-b | SageMaker-RC-ProjectB-ExecutionRole   |
| profile-algo-projx-frank | sm-algo-frank | 算法 | project-x | SageMaker-Algo-ProjectX-ExecutionRole |
| profile-algo-projx-grace | sm-algo-grace | 算法 | project-x | SageMaker-Algo-ProjectX-ExecutionRole |
| profile-algo-projx-henry | sm-algo-henry | 算法 | project-x | SageMaker-Algo-ProjectX-ExecutionRole |
| profile-algo-projy-ivy   | sm-algo-ivy   | 算法 | project-y | SageMaker-Algo-ProjectY-ExecutionRole |
| profile-algo-projy-jack  | sm-algo-jack  | 算法 | project-y | SageMaker-Algo-ProjectY-ExecutionRole |

### 2.2 命名规范

```
User Profile: profile-{team}-{project}-{user}
IAM User:     sm-{team}-{name}

示例:
- profile-rc-proja-alice  ↔  sm-rc-alice
- profile-algo-projx-frank  ↔  sm-algo-frank
```

---

## 3. User Profile 配置

### 3.1 核心配置

| 配置项          | 说明         | 示例                                |
| --------------- | ------------ | ----------------------------------- |
| UserProfileName | Profile 名称 | profile-rc-proja-alice                    |
| DomainId        | 所属 Domain  | d-xxxxxxxxx                         |
| ExecutionRole   | 执行角色     | SageMaker-RC-ProjectA-ExecutionRole |

### 3.2 用户设置 (UserSettings)

| 配置项            | 推荐值                | 说明             |
| ----------------- | --------------------- | ---------------- |
| ExecutionRole     | 项目级 Role           | 每用户按项目分配 |
| SecurityGroups    | [sg-sagemaker-studio] | 继承 Domain      |
| DefaultLandingUri | studio::              | 默认打开 Studio  |

### 3.3 JupyterLab 设置

| 配置项                                 | 推荐值       | 说明     |
| -------------------------------------- | ------------ | -------- |
| DefaultResourceSpec.InstanceType       | ml.t3.medium | 默认实例 |
| DefaultResourceSpec.LifecycleConfigArn | (可选)       | 启动脚本 |

---

## 4. User Profile 与 IAM User 绑定

### 4.1 绑定机制（IAM 模式）

在 IAM 认证模式下，建议将“用户 ↔ Profile”的关系做成**可验证的权限约束**（而不是仅依赖命名约定）：

- **命名约定**：`profile-rc-proja-alice` ↔ `sm-rc-alice`
- **资源标记**：给 User Profile 打上 `Owner=sm-rc-alice`、`Team`、`Project` 等标签
- **访问强制**：通过 IAM Policy 限制：
  - 只允许用户对“自己的 User Profile”执行 `DescribeUserProfile`、`CreatePresignedDomainUrl`
  - 只允许用户在“所属项目 Space”执行 `CreateApp/UpdateApp/DeleteApp`

> 关键点：即使 Console 能“看到”其他 Profile，用户也必须**无法打开**（即无法生成 Presigned URL / 无法创建 App），从而在验收层面可证明。

### 4.2 访问控制

IAM User 只能访问与自己绑定的 User Profile：

```
sm-rc-alice 登录后:
✅ 可以访问: profile-rc-proja-alice
❌ 不能访问: profile-rc-proja-bob
❌ 不能访问: profile-algo-projx-frank
```

### 4.4 可验证方案（验收用例）

建议用以下用例作为“可验收”的定义（通过 Console 或 CLI 均可验证）：

- **用例 A：打开自己 Profile**
  - 预期：成功进入 Studio；可创建/启动自己项目的 App。
- **用例 B：打开他人 Profile**
  - 预期：失败（AccessDenied 或无法进入 Studio）。
- **用例 C：访问他人项目 Space / 创建 App**
  - 预期：失败（AccessDenied）。
- **用例 D：越权访问 S3**
  - 预期：失败（AccessDenied）。

### 4.3 IAM Policy 配置

IAM User 需要以下权限访问自己的 User Profile：

```
权限要点:
1. sagemaker:DescribeUserProfile - 查看 Profile
2. sagemaker:CreatePresignedDomainUrl - 生成登录 URL
3. sagemaker:CreateApp - 创建应用
4. sagemaker:DeleteApp - 删除应用

条件限制:
- Resource: 只能是自己的 UserProfile ARN
- 或使用 Tags 限制
```

---

## 5. Execution Role 绑定

### 5.1 绑定策略

**策略**：同一项目的用户使用相同的 Execution Role

```
项目 A (风控):
├── profile-rc-proja-alice  → SageMaker-RC-ProjectA-ExecutionRole
├── profile-rc-proja-bob    → SageMaker-RC-ProjectA-ExecutionRole
└── profile-rc-proja-carol  → SageMaker-RC-ProjectA-ExecutionRole

项目 X (算法):
├── profile-algo-projx-frank → SageMaker-Algo-ProjectX-ExecutionRole
├── profile-algo-projx-grace → SageMaker-Algo-ProjectX-ExecutionRole
└── profile-algo-projx-henry → SageMaker-Algo-ProjectX-ExecutionRole
```

### 5.2 权限效果

用户在 Notebook 中执行代码时：

- 使用 User Profile 中配置的 Execution Role
- 该 Role 决定了可访问的 S3 Bucket
- 该 Role 决定了可使用的 AWS 服务

---

## 6. 标签设计

### 6.1 必需标签

每个 User Profile 必须包含以下标签：

| Tag Key     | Tag Value  | 示例         |
| ----------- | ---------- | ------------ |
| Team        | {team}     | risk-control |
| Project     | {project}  | project-a    |
| Owner       | {iam-user} | sm-rc-alice  |
| Environment | production | production   |

### 6.2 标签用途

标签可用于：

1. **权限控制**：IAM Policy 中的 Condition
2. **成本分配**：Cost Explorer 分析
3. **资源查找**：按标签筛选 Profile

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
- UserProfileName: profile-{team}-{project}-{user}
- DomainId: d-xxxxxxxxx
- Tags:
    - Key: Team, Value: {team}
    - Key: Project, Value: {project}
    - Key: Owner, Value: sm-{team}-{name}
- UserSettings:
    - ExecutionRole: arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole
    - SecurityGroups: [sg-xxxxxxxxx]
```

### 8.2 批量创建示例

| #   | UserProfileName    | IAM User      | Execution Role | Tags                                 |
| --- | ------------------ | ------------- | -------------- | ------------------------------------ |
| 1   | profile-rc-proja-alice   | sm-rc-alice   | RC-ProjectA    | Team:risk-control, Project:project-a |
| 2   | profile-rc-proja-bob     | sm-rc-bob     | RC-ProjectA    | Team:risk-control, Project:project-a |
| 3   | profile-algo-projx-frank | sm-algo-frank | Algo-ProjectX  | Team:algorithm, Project:project-x    |

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

### 10.1 创建单个 User Profile

```bash
# 创建 User Profile
aws sagemaker create-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-proja-alice \
  --user-settings '{
    "ExecutionRole": "arn:aws:iam::{account-id}:role/SageMaker-RC-ProjectA-ExecutionRole",
    "SecurityGroups": ["sg-sagemaker-studio"]
  }' \
  --tags \
    Key=Team,Value=risk-control \
    Key=Project,Value=project-a \
    Key=Owner,Value=sm-rc-alice \
    Key=Environment,Value=production
```

### 10.2 查询 User Profile

```bash
# 列出 Domain 下所有 User Profiles
aws sagemaker list-user-profiles --domain-id d-xxxxxxxxx

# 查看单个 Profile 详情
aws sagemaker describe-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-proja-alice
```

### 10.3 更新 User Profile

```bash
# 更新 Execution Role（用户换项目时）
aws sagemaker update-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-proja-alice \
  --user-settings '{
    "ExecutionRole": "arn:aws:iam::{account-id}:role/SageMaker-RC-ProjectB-ExecutionRole"
  }'
```

### 10.4 删除 User Profile

```bash
# 先删除用户的所有 Apps
aws sagemaker list-apps \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-proja-alice

# 删除每个 App（如有）
aws sagemaker delete-app \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-proja-alice \
  --app-type JupyterLab \
  --app-name default

# 等待 App 删除完成后，删除 Profile
aws sagemaker delete-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-proja-alice
```

---

## 11. Lifecycle Configuration

> 📌 Lifecycle Configuration 在 Domain 级别配置，所有 User Profile 继承。详见 `05-sagemaker-domain.md` § 11。

如需为特定用户配置不同的 Lifecycle Config：

```bash
aws sagemaker update-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-proja-alice \
  --user-settings '{
    "JupyterLabAppSettings": {
      "DefaultResourceSpec": {
        "LifecycleConfigArn": "arn:aws:sagemaker:{region}:{account-id}:studio-lifecycle-config/custom-config"
      }
    }
  }'
```

---

## 12. 批量创建脚本

### 12.1 用户配置文件 `users.csv`

```csv
profile_name,iam_user,team,project,execution_role
profile-rc-proja-alice,sm-rc-alice,risk-control,project-a,SageMaker-RC-ProjectA-ExecutionRole
profile-rc-proja-bob,sm-rc-bob,risk-control,project-a,SageMaker-RC-ProjectA-ExecutionRole
profile-rc-proja-carol,sm-rc-carol,risk-control,project-a,SageMaker-RC-ProjectA-ExecutionRole
profile-rc-projb-david,sm-rc-david,risk-control,project-b,SageMaker-RC-ProjectB-ExecutionRole
profile-rc-projb-emma,sm-rc-emma,risk-control,project-b,SageMaker-RC-ProjectB-ExecutionRole
profile-algo-projx-frank,sm-algo-frank,algorithm,project-x,SageMaker-Algo-ProjectX-ExecutionRole
profile-algo-projx-grace,sm-algo-grace,algorithm,project-x,SageMaker-Algo-ProjectX-ExecutionRole
profile-algo-projx-henry,sm-algo-henry,algorithm,project-x,SageMaker-Algo-ProjectX-ExecutionRole
profile-algo-projy-ivy,sm-algo-ivy,algorithm,project-y,SageMaker-Algo-ProjectY-ExecutionRole
profile-algo-projy-jack,sm-algo-jack,algorithm,project-y,SageMaker-Algo-ProjectY-ExecutionRole
```

### 12.2 批量创建脚本 `create-user-profiles.sh`

```bash
#!/bin/bash
# create-user-profiles.sh - 批量创建 User Profiles
# 用法: ./create-user-profiles.sh <domain-id> <account-id> <users.csv>

set -e

DOMAIN_ID="${1:?Usage: $0 <domain-id> <account-id> <users.csv>}"
ACCOUNT_ID="${2:?Usage: $0 <domain-id> <account-id> <users.csv>}"
USERS_FILE="${3:?Usage: $0 <domain-id> <account-id> <users.csv>}"
SECURITY_GROUP="sg-sagemaker-studio"  # 按需修改

# 跳过 CSV 头行
tail -n +2 "$USERS_FILE" | while IFS=',' read -r profile_name iam_user team project execution_role; do
    echo "Creating User Profile: $profile_name"

    # 检查是否已存在
    if aws sagemaker describe-user-profile \
        --domain-id "$DOMAIN_ID" \
        --user-profile-name "$profile_name" >/dev/null 2>&1; then
        echo "  → Already exists, skipping."
        continue
    fi

    # 创建 User Profile
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
            Key=Environment,Value=production

    echo "  → Created successfully."

    # 避免 API 限流
    sleep 1
done

echo ""
echo "Batch creation completed. Verifying..."
aws sagemaker list-user-profiles --domain-id "$DOMAIN_ID" --query 'UserProfiles[].UserProfileName'
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
- [ ] Execution Roles 已创建
- [ ] 确认用户-项目对应关系

### 创建时

- [ ] 使用正确的命名规范
- [ ] 绑定正确的 Execution Role
- [ ] 添加必需的标签

### 创建后

- [ ] 验证用户可以登录
- [ ] 验证用户只能看到自己的 Profile
- [ ] 验证 Execution Role 权限正确
- [ ] 创建对应的 Space（见下一文档）
