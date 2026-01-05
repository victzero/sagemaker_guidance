# 04 - S3 数据管理

> 本文档描述 S3 Bucket 结构、权限策略和数据生命周期管理

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符          | 说明               | 示例值                                 |
| --------------- | ------------------ | -------------------------------------- |
| `{company}`     | 公司/组织名称前缀  | `acme`                                 |
| `{account-id}`  | AWS 账号 ID        | `123456789012`                         |
| `{team}`        | 团队缩写           | `rc`、`algo`                           |
| `{project}`     | 项目名称           | `project-a`、`project-x`               |
| `{user}`        | 用户名             | `alice`、`frank`                       |
| `{cost-center}` | 成本中心代码       | `ML-001`                               |
| `{vpc-id}`      | VPC ID（可选）     | `vpc-0abc123def456`                    |
| `{key-id}`      | KMS Key ID（可选） | `12345678-1234-1234-1234-123456789abc` |
| `{region}`      | AWS 区域           | `ap-southeast-1`                       |

---

## 1. Bucket 规划

### 1.1 Bucket 策略

**方案选择**：每项目独立 Bucket

| 方案                  | 优点               | 缺点           | 选择 |
| --------------------- | ------------------ | -------------- | ---- |
| 单一 Bucket + Prefix  | 管理简单           | 权限控制复杂   | ❌   |
| **每项目独立 Bucket** | 隔离清晰、权限简单 | Bucket 数量多  | ✅   |
| 每团队独立 Bucket     | 折中               | 项目间隔离不足 | ❌   |

### 1.2 Bucket 清单

| Bucket 名称                        | 团队 | 项目         | 用途               |
| ---------------------------------- | ---- | ------------ | ------------------ |
| `{company}-sm-rc-fraud-detection`  | 风控 | 欺诈检测     | 欺诈检测项目数据   |
| `{company}-sm-rc-aml`              | 风控 | 反洗钱       | 反洗钱项目数据     |
| `{company}-sm-algo-recommendation` | 算法 | 推荐系统     | 推荐系统项目数据   |
| `{company}-sm-shared-assets`       | 共享 | -            | 共享模型、脚本     |

> **命名规范**: `{company}-sm-{team}-{project}`，其中 `team` 和 `project` 使用 kebab-case。

### 1.3 命名规范

```
{company}-sm-{team}-{project}

示例:
- acme-sm-rc-fraud-detection    # 风控团队欺诈检测项目
- acme-sm-rc-aml                # 风控团队反洗钱项目
- acme-sm-algo-recommendation   # 算法团队推荐系统项目
- acme-sm-shared-assets         # 共享资源 Bucket
```

> **与 IAM 命名一致性**: Bucket 名称中的 `{team}` 和 `{project}` 与 IAM 用户/组命名保持一致。详见 [02-iam-design.md](02-iam-design.md)。

---

## 2. Bucket 内部结构

### 2.1 标准目录结构

每个项目 Bucket 采用统一的目录结构：

```
{company}-sm-{team}-{project}/
│
├── raw/                    # 原始数据
│   ├── uploads/            # 上传的原始文件
│   └── external/           # 外部导入数据
│
├── processed/              # 处理后数据
│   ├── cleaned/            # 清洗后数据
│   └── transformed/        # 转换后数据
│
├── features/               # 特征数据
│   └── v{version}/         # 版本化特征
│
├── models/                 # 模型文件
│   ├── training/           # 训练中间文件
│   ├── artifacts/          # 模型产物
│   └── registry/           # 模型注册
│
├── notebooks/              # Notebook 备份
│   └── archived/           # 归档的 Notebook
│
├── outputs/                # 输出结果
│   ├── reports/            # 分析报告
│   └── predictions/        # 预测结果
│
└── temp/                   # 临时文件
    └── {user}/             # 按用户隔离
```

### 2.2 共享 Bucket 结构

```
{company}-sm-shared-assets/
│
├── scripts/                # 共享脚本
│   ├── preprocessing/      # 预处理脚本
│   └── utils/              # 工具脚本
│
├── containers/             # 容器配置
│   └── dockerfiles/        # Dockerfile
│
├── datasets/               # 共享数据集
│   └── reference/          # 参考数据
│
└── documentation/          # 文档
```

---

## 3. Bucket 配置

### 3.1 基础配置

| 配置项        | 值             | 说明                           |
| ------------- | -------------- | ------------------------------ |
| Region        | ap-southeast-1 | 与 VPC 同 Region               |
| Versioning    | Enabled        | 版本控制                       |
| Encryption    | SSE-S3         | 默认加密（或 SSE-KMS，见 3.3） |
| Public Access | Block All      | 禁止公开访问                   |
| Object Lock   | Disabled       | 按需启用                       |

### 3.2 标签规范

每个 Bucket 必须包含以下标签：

| Tag Key     | Tag Value          | 示例               |
| ----------- | ------------------ | ------------------ |
| Team        | {team}             | risk-control       |
| Project     | {project}          | project-a          |
| Environment | production         | production         |
| CostCenter  | {cost-center}      | ML-001             |
| ManagedBy   | sagemaker-platform | sagemaker-platform |

### 3.3 SSE-KMS 加密（可选）

> 📌 SSE-KMS 为可选配置，适用于有合规审计或细粒度密钥管理需求的场景。一般开发/实验环境使用 SSE-S3 即可。

#### SSE-S3 vs SSE-KMS 对比

| 特性       | SSE-S3        | SSE-KMS                        |
| ---------- | ------------- | ------------------------------ |
| 密钥管理   | AWS 全托管    | 客户可控（CMK）                |
| 密钥轮换   | 自动          | 可自定义策略                   |
| 访问审计   | ❌ 无详细日志 | ✅ CloudTrail 记录每次密钥使用 |
| 权限分离   | ❌ 无         | ✅ 可单独控制 kms:Decrypt 权限 |
| 跨账号控制 | ❌ 无         | ✅ 可通过 Key Policy 精细控制  |
| 额外成本   | 免费          | $1/月/密钥 + API 调用费        |
| 适用场景   | 一般开发/实验 | 合规审计、敏感数据、多账号     |

#### 何时选择 SSE-KMS

- **合规要求**：需要证明"谁在何时访问了数据"（审计日志）
- **敏感数据**：PII、金融数据等需要额外保护层
- **权限分离**：希望独立于 S3 权限控制解密能力
- **多账号架构**：需要跨账号共享并精确控制访问
- **密钥轮换策略**：需要自定义密钥轮换周期

#### SSE-KMS 配置示例

**1. 创建 KMS Key（建议为 SageMaker 项目专用）**

```bash
aws kms create-key \
  --description "SageMaker ML Platform - S3 Encryption Key" \
  --tags TagKey=Purpose,TagValue=sagemaker-s3-encryption
```

**2. 设置 Bucket 默认加密**

```json
{
  "Rules": [
    {
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "arn:aws:kms:{region}:{account-id}:key/{key-id}"
      },
      "BucketKeyEnabled": true
    }
  ]
}
```

> 💡 **BucketKeyEnabled: true** 可显著降低 KMS API 调用成本（减少 99%）。

**3. KMS Key Policy 示例（允许 SageMaker Execution Role 使用）**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSageMakerExecutionRoles",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account-id}:root"
      },
      "Action": ["kms:Decrypt", "kms:GenerateDataKey*"],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::{account-id}:role/SageMaker-*-ExecutionRole"
        }
      }
    },
    {
      "Sid": "AllowKeyAdministration",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account-id}:root"
      },
      "Action": [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion"
      ],
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::{account-id}:group/sagemaker-admins"
        }
      }
    }
  ]
}
```

#### 不选择 SSE-KMS 的理由（SSE-S3 足够的场景）

- 无外部合规审计要求
- 数据已在 VPC 内部隔离，无跨账号访问
- 希望简化运维，减少额外配置
- 成本敏感，避免 KMS API 调用费

---

## 4. 权限策略设计

### 4.1 Bucket Policy 设计原则

1. **默认拒绝**：只允许明确授权的访问
2. **最小权限**：只授予必要操作
3. **基于角色**：通过 Execution Role 访问

### 4.2 项目 Bucket Policy 模板

```
Policy 要点:
1. 允许指定 Execution Role 访问
2. 允许项目成员通过 Console 查看
3. 拒绝其他所有访问
4. 条件限制 VPC 内访问
```

**允许的操作**:

- s3:GetObject
- s3:PutObject
- s3:DeleteObject
- s3:ListBucket
- s3:GetBucketLocation

**主体**:

- `arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole`
- `arn:aws:iam::{account-id}:user/sm-{team}-*`（项目成员）

### 4.3 共享 Bucket Policy

```
Policy 要点:
1. 允许所有 SageMaker Execution Role 只读
2. 允许所有 SageMaker 用户 (sm-*) 只读
3. 管理员 (sm-admin-*) 可写入
```

**允许的操作（普通用户）**:

- s3:GetObject
- s3:ListBucket
- s3:GetBucketLocation

### 4.4 4 角色设计与 S3 访问（更新）

生产级 4 角色分离设计中，各角色对 S3 的访问权限如下：

| 角色             | S3 访问需求                              | 权限范围                    |
| ---------------- | ---------------------------------------- | --------------------------- |
| **ExecutionRole**| Notebook 开发、提交作业                  | 项目 Bucket 读写 + 共享只读 |
| **TrainingRole** | Training Job 读取数据、写入模型          | 项目 Bucket 读写            |
| **ProcessingRole**| Processing Job 数据处理、特征工程       | 项目 Bucket 读写            |
| **InferenceRole** | Endpoint 加载模型、写入预测结果（只读优先）| 项目 Bucket 只读为主        |

> **最小权限原则**: InferenceRole 通常只需要读取模型和配置，限制写权限可降低安全风险。

---

## 5. 生命周期规则

### 5.1 自动清理规则

| 路径                   | 规则             | 天数 | 说明             |
| ---------------------- | ---------------- | ---- | ---------------- |
| temp/\*                | Delete           | 7    | 临时文件自动清理 |
| models/training/\*     | Transition to IA | 30   | 训练文件降级存储 |
| notebooks/archived/\*  | Transition to IA | 60   | 归档 Notebook    |
| outputs/predictions/\* | Delete           | 90   | 旧预测结果清理   |

### 5.2 版本管理规则

| 规则           | 设置  | 说明               |
| -------------- | ----- | ------------------ |
| 非当前版本过期 | 90 天 | 保留最近 90 天版本 |
| 删除标记清理   | 1 天  | 清理空删除标记     |
| 不完整上传清理 | 7 天  | 清理失败的多段上传 |

---

## 6. 访问路径

### 6.1 Notebook 内访问

```
Notebook → Execution Role → S3 Bucket

权限检查:
1. Execution Role 是否有 S3 权限
2. Bucket Policy 是否允许该 Role
3. VPC Endpoint 是否配置正确
```

### 6.2 Console 访问

```
IAM User → Console → S3 Bucket

权限检查:
1. IAM User 是否有 S3 权限
2. Bucket Policy 是否允许该 User
```

---

## 7. 数据管理最佳实践

### 7.1 数据组织

| 实践       | 说明                       |
| ---------- | -------------------------- |
| 版本化目录 | features/v1/, features/v2/ |
| 日期分区   | raw/uploads/2024/01/01/    |
| 元数据文件 | 每个目录包含 README.md     |

### 7.2 数据安全

| 实践       | 说明                           |
| ---------- | ------------------------------ |
| 禁止公开   | Block Public Access            |
| 加密存储   | SSE-S3（或 SSE-KMS，按需选择） |
| 访问日志   | 启用 Server Access Logging     |
| 跨账号限制 | Bucket Policy 限制 Principal   |

### 7.3 成本控制

| 实践         | 说明                      |
| ------------ | ------------------------- |
| 生命周期规则 | 自动清理临时文件          |
| 智能分层     | Intelligent-Tiering       |
| 存储类别     | 冷数据用 S3-IA 或 Glacier |

---

## 8. 权限绑定关系

### 8.1 4 角色 → Bucket（生产级）

每个项目有 4 个专用角色，各自的 S3 访问权限如下：

| 角色类型       | 角色名称示例                                   | 项目 Bucket          | 共享 Bucket |
| -------------- | ---------------------------------------------- | -------------------- | ----------- |
| ExecutionRole  | SageMaker-RiskControl-FraudDetection-ExecutionRole | 读写                 | 只读        |
| TrainingRole   | SageMaker-RiskControl-FraudDetection-TrainingRole  | 读写                 | 只读        |
| ProcessingRole | SageMaker-RiskControl-FraudDetection-ProcessingRole| 读写                 | 只读        |
| InferenceRole  | SageMaker-RiskControl-FraudDetection-InferenceRole | 只读（最小权限）     | 只读        |

> **注意**: Execution Role 使用默认 IAM 路径 (`/`)，不使用 `IAM_PATH`，以确保 SageMaker 服务兼容性。

### 8.2 Execution Role → Bucket（简化视图）

| Execution Role                                     | 可访问 Bucket                                                    |
| -------------------------------------------------- | ---------------------------------------------------------------- |
| SageMaker-RiskControl-FraudDetection-ExecutionRole | {company}-sm-rc-fraud-detection, {company}-sm-shared-assets (只读) |
| SageMaker-RiskControl-AML-ExecutionRole            | {company}-sm-rc-aml, {company}-sm-shared-assets (只读)           |
| SageMaker-Algorithm-Recommendation-ExecutionRole   | {company}-sm-algo-recommendation, {company}-sm-shared-assets (只读) |

### 8.4 IAM User → Bucket (Console 访问)

| User Group                   | 可访问 Bucket                    |
| ---------------------------- | -------------------------------- |
| sagemaker-rc-fraud-detection | {company}-sm-rc-fraud-detection  |
| sagemaker-rc-aml             | {company}-sm-rc-aml              |
| sagemaker-algo-recommendation| {company}-sm-algo-recommendation |

> **命名说明**:
> - 用户名格式: `sm-{team}-{name}` (如 `sm-rc-alice`)
> - 组名格式: `sagemaker-{team}-{project}` (如 `sagemaker-rc-fraud-detection`)
> - 详见 [02-iam-design.md](02-iam-design.md) 中的命名规范

---

## 9. Bucket Policy JSON 模板

### 9.1 项目 Bucket Policy（完整示例）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowExecutionRoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-{team}-{project}",
        "arn:aws:s3:::{company}-sm-{team}-{project}/*"
      ]
    },
    {
      "Sid": "AllowProjectMembersConsoleAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account-id}:root"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-{team}-{project}",
        "arn:aws:s3:::{company}-sm-{team}-{project}/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:username": "sm-{team}-*"
        }
      }
    },
    {
      "Sid": "DenyNonVPCAccess",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::{company}-sm-{team}-{project}",
        "arn:aws:s3:::{company}-sm-{team}-{project}/*"
      ],
      "Condition": {
        "StringNotEquals": {
          "aws:SourceVpc": "{vpc-id}"
        },
        "Bool": {
          "aws:ViaAWSService": "false"
        }
      }
    }
  ]
}
```

> **说明**：`DenyNonVPCAccess` 规则可选，启用后仅允许 VPC 内访问。如需 Console 访问，需通过 VPN/Direct Connect 接入 VPC。

### 9.2 共享 Bucket Policy（只读访问）

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAllExecutionRolesReadOnly",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account-id}:root"
      },
      "Action": ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": [
        "arn:aws:s3:::{company}-sm-shared-assets",
        "arn:aws:s3:::{company}-sm-shared-assets/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::{account-id}:role/SageMaker-*-ExecutionRole"
        }
      }
    },
    {
      "Sid": "AllowAllSageMakerUsersReadOnly",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account-id}:root"
      },
      "Action": ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": [
        "arn:aws:s3:::{company}-sm-shared-assets",
        "arn:aws:s3:::{company}-sm-shared-assets/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:username": "sm-*"
        }
      }
    },
    {
      "Sid": "AllowAdminFullAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account-id}:root"
      },
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::{company}-sm-shared-assets",
        "arn:aws:s3:::{company}-sm-shared-assets/*"
      ],
      "Condition": {
        "StringLike": {
          "aws:username": "sm-admin-*"
        }
      }
    }
  ]
}
```

> **说明**:
> - `AllowAllExecutionRolesReadOnly`: 允许所有项目的 Execution Role 只读访问（用于 Notebook/作业）
> - `AllowAllSageMakerUsersReadOnly`: 允许所有 SageMaker 用户 (`sm-*`) 通过 Console 只读访问
> - `AllowAdminFullAccess`: 只有管理员用户 (`sm-admin-*`) 可以写入共享 Bucket

---

## 10. 生命周期规则 JSON 模板

### 10.1 完整生命周期配置

```json
{
  "Rules": [
    {
      "ID": "CleanupTempFiles",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "temp/"
      },
      "Expiration": {
        "Days": 7
      }
    },
    {
      "ID": "TransitionTrainingModels",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "models/training/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        }
      ]
    },
    {
      "ID": "TransitionArchivedNotebooks",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "notebooks/archived/"
      },
      "Transitions": [
        {
          "Days": 60,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 180,
          "StorageClass": "GLACIER"
        }
      ]
    },
    {
      "ID": "CleanupOldPredictions",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "outputs/predictions/"
      },
      "Expiration": {
        "Days": 90
      }
    },
    {
      "ID": "CleanupNoncurrentVersions",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    },
    {
      "ID": "CleanupDeleteMarkers",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": {
        "ExpiredObjectDeleteMarker": true
      }
    },
    {
      "ID": "CleanupIncompleteUploads",
      "Status": "Enabled",
      "Filter": {},
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
```

### 10.2 AWS CLI 应用命令

```bash
# 将生命周期配置应用到 Bucket
aws s3api put-bucket-lifecycle-configuration \
  --bucket {company}-sm-{team}-{project} \
  --lifecycle-configuration file://lifecycle-config.json
```

---

## 11. 跨 Region 复制（可选）

> 📌 跨 Region 复制适用于灾备或多区域协作场景，非必需配置。

### 11.1 适用场景

| 场景          | 说明                   | 建议         |
| ------------- | ---------------------- | ------------ |
| 灾备需求      | 重要数据异地备份       | 按需启用     |
| 多区域协作    | 跨区域团队共享数据     | 按需启用     |
| 低延迟访问    | 就近访问数据           | 按需启用     |
| 一般开发/实验 | 无特殊合规或可用性要求 | **暂不需要** |

### 11.2 复制规则配置（如需启用）

```json
{
  "Role": "arn:aws:iam::{account-id}:role/S3ReplicationRole",
  "Rules": [
    {
      "ID": "ReplicateModels",
      "Status": "Enabled",
      "Priority": 1,
      "Filter": {
        "Prefix": "models/artifacts/"
      },
      "Destination": {
        "Bucket": "arn:aws:s3:::{company}-sm-{team}-{project}-replica",
        "StorageClass": "STANDARD_IA"
      },
      "DeleteMarkerReplication": {
        "Status": "Disabled"
      }
    }
  ]
}
```

### 11.3 前置条件

- [ ] 源 Bucket 和目标 Bucket 均启用版本控制
- [ ] 创建 S3 复制 IAM Role（具有源 Bucket 读权限 + 目标 Bucket 写权限）
- [ ] 目标 Bucket 已创建（可以是相同账号或跨账号）

---

## 12. 检查清单

### 创建前

- [ ] 确认公司名称前缀
- [ ] 确认项目清单
- [ ] 确认 Region
- [ ] 确认 IAM Roles 已创建（Execution/Training/Processing/Inference）

### 创建时

- [ ] 启用版本控制
- [ ] 启用默认加密 (SSE-S3 或 SSE-KMS)
- [ ] 阻止公开访问
- [ ] 添加标签 (Team, Project, Environment, CostCenter, ManagedBy)
- [ ] 创建目录结构

### 创建后

- [ ] 配置 Bucket Policy
- [ ] 配置生命周期规则
- [ ] 验证 Execution Role 访问
- [ ] 验证 Training/Processing/Inference Role 访问
- [ ] 验证 IAM User Console 访问

---

## 13. 实现脚本

S3 配置由自动化脚本实现，详见 [scripts/03-s3/README.md](../scripts/03-s3/README.md)。

### 脚本清单

| 脚本                       | 用途                      |
| -------------------------- | ------------------------- |
| `00-init.sh`               | 初始化和环境变量验证      |
| `01-create-buckets.sh`     | 创建 S3 Buckets           |
| `02-configure-policies.sh` | 配置 Bucket Policies      |
| `03-configure-lifecycle.sh`| 配置生命周期规则          |
| `setup-all.sh`             | 一次性创建所有资源        |
| `verify.sh`                | 验证配置                  |
| `cleanup.sh`               | 清理资源（⚠️ 危险）       |

### 环境变量

| 变量                     | 说明               | 默认值   |
| ------------------------ | ------------------ | -------- |
| `COMPANY`                | 公司前缀           | 必填     |
| `ENCRYPTION_TYPE`        | 加密类型           | SSE-S3   |
| `KMS_KEY_ID`             | KMS 密钥 ID        | -        |
| `ENABLE_VERSIONING`      | 启用版本控制       | true     |
| `ENABLE_LIFECYCLE_RULES` | 启用生命周期规则   | true     |
| `RESTRICT_TO_VPC`        | 限制 VPC 内访问    | false    |
| `VPC_ID`                 | VPC ID（可选）     | -        |
| `CREATE_SHARED_BUCKET`   | 创建共享 Bucket    | true     |
