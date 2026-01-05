# IAM Policy Templates

本目录包含 SageMaker IAM 策略的模板文件，与 Shell 脚本分离以便于维护和审计。

## 文件说明

| 文件                              | 说明                           | 变量                                                         |
| --------------------------------- | ------------------------------ | ------------------------------------------------------------ |
| `trust-policy-sagemaker.json`     | Execution Role 信任策略        | 无（静态）                                                   |
| `base-access.json.tpl`            | 用户基础访问策略               | `AWS_REGION`, `AWS_ACCOUNT_ID`                               |
| `team-access.json.tpl`            | 团队访问策略                   | `AWS_REGION`, `AWS_ACCOUNT_ID`, `COMPANY`, `TEAM`            |
| `project-access.json.tpl`         | 项目访问策略                   | `AWS_REGION`, `AWS_ACCOUNT_ID`, `COMPANY`, `TEAM`, `PROJECT` |
| `execution-role.json.tpl`         | ExecutionRole（开发/Notebook） | `AWS_REGION`, `AWS_ACCOUNT_ID`, `COMPANY`, `TEAM`, `PROJECT`, `TEAM_FULLNAME`, `PROJECT_FULLNAME` |
| `training-role.json.tpl`          | TrainingRole（训练专用）       | `AWS_REGION`, `AWS_ACCOUNT_ID`, `COMPANY`, `TEAM`, `PROJECT`, `TEAM_FULLNAME`, `PROJECT_FULLNAME` |
| `processing-role.json.tpl`        | ProcessingRole（处理专用）     | `AWS_REGION`, `AWS_ACCOUNT_ID`, `COMPANY`, `TEAM`, `PROJECT`, `TEAM_FULLNAME`, `PROJECT_FULLNAME` |
| `inference-role.json.tpl`         | InferenceRole（推理专用）      | `AWS_REGION`, `AWS_ACCOUNT_ID`, `COMPANY`, `TEAM`, `PROJECT`, `TEAM_FULLNAME`, `PROJECT_FULLNAME` |
| `user-boundary.json.tpl`          | 用户权限边界                   | `AWS_ACCOUNT_ID`, `COMPANY`                                  |
| `readonly.json.tpl`               | 只读访问策略                   | `AWS_REGION`, `AWS_ACCOUNT_ID`, `COMPANY`                    |
| `self-service.json.tpl`           | 用户自助服务策略               | `AWS_ACCOUNT_ID`, `IAM_PATH`                                 |
| `studio-app-permissions.json.tpl` | Studio App 用户隔离            | `AWS_REGION`, `AWS_ACCOUNT_ID`                               |
| `mlflow-app-access.json.tpl`      | MLflow 实验追踪                | `AWS_REGION`, `AWS_ACCOUNT_ID`                               |

## Trust Policy 说明

### User Profile Execution Role

`trust-policy-sagemaker.json` 用于绑定到 User Profile 的 Execution Role：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sagemaker.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**注意**: 这是标准的 SageMaker 信任策略，只包含 `sts:AssumeRole`。

### Execution Role 权限层次

User Profile 绑定的 Execution Role 包含以下权限（按附加顺序）：

1. **AmazonSageMakerFullAccess** (AWS 托管策略)

   - SageMaker 全功能权限
   - Processing Job / Training Job / Inference
   - 必须先附加此策略

2. **Canvas 策略组** (AWS 托管策略, 可选, 默认开启)

   - SageMaker Canvas 低代码 ML
   - AI 服务 (Bedrock, Textract 等)

3. **Studio App Permissions** (`studio-app-permissions.json.tpl`, 始终启用)

   - 用户 Profile 隔离
   - Private/Shared Space 权限控制
   - 防止用户误删他人资源

4. **MLflow App Access** (`mlflow-app-access.json.tpl`, 可选, 默认开启)

   - MLflow 实验追踪
   - Model Registry 集成

5. **项目自定义策略** (`execution-role.json.tpl`)
   - S3 项目桶访问
   - CloudWatch Logs
   - ECR 镜像仓库
   - Amazon Q / Data Science Assistant

## 4 角色分离设计（生产级）

### 角色权限对比矩阵

| 权限类型 | ExecutionRole | TrainingRole | ProcessingRole | InferenceRole |
| -------- | :-----------: | :----------: | :------------: | :-----------: |
| AmazonSageMakerFullAccess | ✅ | ❌ | ❌ | ❌ |
| S3 完整读写 | ✅ | ❌ | ❌ | ❌ |
| S3 训练数据读取 | ✅ | ✅ | ❌ | ❌ |
| S3 模型输出写入 | ✅ | ✅ | ❌ | ❌ |
| S3 原始数据读取 | ✅ | ❌ | ✅ | ❌ |
| S3 处理输出写入 | ✅ | ❌ | ✅ | ❌ |
| S3 模型只读 | ✅ | ❌ | ❌ | ✅ |
| S3 推理输出 | ✅ | ❌ | ❌ | ✅ |
| ECR 读写 | ✅ | ❌ | ❌ | ❌ |
| ECR 只读 | ✅ | ✅ | ✅ | ✅ |
| Training/HPO 操作 | ✅ | ✅ | ❌ | ❌ |
| Processing 操作 | ✅ | ❌ | ✅ | ❌ |
| Inference 操作 | ✅ | ❌ | ❌ | ✅ |
| Model Registry 写入 | ✅ | ✅ | ❌ | ❌ |
| Model Registry 只读 | ✅ | ✅ | ❌ | ✅ |
| Feature Store | ✅ | ❌ | ✅ | ❌ |
| Glue/Athena | ❌ | ❌ | ✅ | ❌ |
| Pass Role 到其他角色 | ✅ | ❌ | ❌ | ❌ |

### Training Role（训练专用）

`training-role.json.tpl` 用于模型训练，权限包括：

- S3 训练数据读取 (`data/*`, `datasets/*`, `processed/*`)
- S3 模型输出写入 (`models/*`, `training-output/*`, `checkpoints/*`)
- ECR 只读（拉取训练镜像）
- Model Registry 写入（注册模型）
- 实验追踪（Experiments API）
- Training/HPO 操作

### Processing Role（处理专用）

`processing-role.json.tpl` 用于数据处理，权限包括：

- S3 原始数据读取 (`data/*`, `raw/*`, `datasets/*`)
- S3 处理输出写入 (`processed/*`, `features/*`)
- ECR 只读（拉取处理镜像）
- Processing/Data Wrangler 操作
- Feature Store 访问
- Glue/Athena 数据目录访问

### Inference Role（推理专用）

`inference-role.json.tpl` 用于生产模型部署，遵循 **最小权限原则**：

- S3 模型只读 (`models/*`, `inference/*`)
- S3 推理输出 (`inference/output/*`, `batch-transform/*`)
- ECR 只读（拉取推理镜像）
- Model Registry 只读
- Inference 操作（Endpoint, Transform）

### 使用场景

```python
# ============================================
# Notebook 开发：使用 ExecutionRole
# ============================================
# User Profile 绑定，自动使用
# 可以：探索数据、提交作业、查看日志

# ============================================
# 训练作业：使用 TrainingRole
# ============================================
from sagemaker.estimator import Estimator

estimator = Estimator(
    role="arn:aws:iam::xxx:role/SageMaker-Team-Project-TrainingRole",  # ← 训练专用
    image_uri="...",
    instance_type="ml.m5.xlarge",
)
estimator.fit(...)

# ============================================
# 处理作业：使用 ProcessingRole
# ============================================
from sagemaker.processing import ScriptProcessor

processor = ScriptProcessor(
    role="arn:aws:iam::xxx:role/SageMaker-Team-Project-ProcessingRole",  # ← 处理专用
    image_uri="...",
    instance_type="ml.m5.xlarge",
)
processor.run(...)

# ============================================
# 生产部署：使用 InferenceRole
# ============================================
from sagemaker import Model

model = Model(
    role="arn:aws:iam::xxx:role/SageMaker-Team-Project-InferenceRole",  # ← 推理专用
    image_uri="...",
    model_data="s3://bucket/models/model.tar.gz",
)
predictor = model.deploy(...)
```

## 变量替换

模板文件使用 `${VAR_NAME}` 格式的变量占位符。Shell 脚本会通过 `envsubst` 或 `sed` 进行替换：

```bash
# 示例：渲染模板
export AWS_REGION="ap-southeast-1"
export AWS_ACCOUNT_ID="123456789012"
export COMPANY="acme"
export TEAM="rc"
export PROJECT="fraud-detection"

envsubst < project-access.json.tpl > /tmp/policy.json
```

## IAM Policy 变量说明

| 变量                | AWS IAM 特殊语法 | 说明                                     |
| ------------------- | ---------------- | ---------------------------------------- |
| `${aws:username}`   | ✅ 是            | IAM 策略条件变量，运行时替换为当前用户名 |
| `${AWS_REGION}`     | ❌ 否            | 脚本变量，构建时替换                     |
| `${AWS_ACCOUNT_ID}` | ❌ 否            | 脚本变量，构建时替换                     |

**注意**: `${aws:username}` 是 IAM 策略的条件变量，不能被 envsubst 替换，需要保留原样。

## Domain Default Execution Role

Domain 默认 Execution Role 只附加 **AmazonSageMakerFullAccess**：

- 提供 SageMaker 基础功能
- 不包含项目特定的 S3 权限
- User Profile 可以覆盖使用项目 Execution Role

## 权限设计原则

1. **最小权限**: 每个 Role 只包含必要的权限
2. **分层设计**: AWS 托管策略 + 自定义策略
3. **项目隔离**: S3 权限限定到项目桶
4. **安全边界**: Permissions Boundary 防止权限提升

## 安全加固设计

### S3 访问控制

| 控制点 | 实现方式 | 效果 |
|--------|----------|------|
| 禁止浏览桶列表 | `DenyS3BucketListing` 拒绝 `s3:ListAllMyBuckets` | 用户无法看到账号内所有桶 |
| 限制桶访问范围 | `DenyAccessToOtherBuckets` + `NotResource` | 用户只能访问公司 SM 桶和 SageMaker 默认桶 |
| 项目级隔离 | `project-access.json.tpl` 限定到具体项目桶 | 用户只能访问自己项目的桶 |
| 禁止桶管理 | `DenyS3BucketAdmin` 拒绝 Create/Delete Bucket | 用户无法创建或删除桶 |

**用户访问 S3 的方式**:
- ❌ 不能通过 S3 Console 浏览所有桶
- ✅ 通过 URL 直接访问项目桶: `s3://${COMPANY}-sm-${TEAM}-${PROJECT}/`
- ✅ 通过 SageMaker SDK/boto3 读写文件

### SageMaker 资源隔离

| 控制点 | 实现方式 | 效果 |
|--------|----------|------|
| User Profile 隔离 | `sagemaker:ResourceTag/Owner` 条件 | 用户只能操作自己的 Profile |
| Space/App 隔离 | `sagemaker:OwnerUserProfileArn` 条件 | 用户只能管理自己创建的 Space 和 App |
| 项目 Space 访问 | `sagemaker:ResourceTag/Project` 条件 | 用户只能访问所属项目的共享 Space |
| 禁止管理操作 | `DenySageMakerAdminActions` | 用户无法创建/删除 Domain、UserProfile 和 Space |

**跨项目隔离说明**:
- `sagemaker:List*` 和 `sagemaker:Describe*` 对所有资源可见（SageMaker Studio Console 需要）
- 实际的 Create/Update/Delete 操作通过标签条件限制
- 敏感数据通过 S3 项目桶隔离保护

### 安全边界 (Permissions Boundary)

`user-boundary.json.tpl` 定义了用户权限的绝对上限：

```
┌─────────────────────────────────────────────────┐
│            Permissions Boundary                  │
│  ┌───────────────────────────────────────────┐  │
│  │         实际授予的权限 (Policy)           │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │      用户有效权限                   │  │  │
│  │  │   (Policy ∩ Boundary)              │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

**Deny 语句优先级**: Boundary 中的 Deny 语句无法被任何 Allow 覆盖

### MFA 强制要求

用户必须启用 MFA 才能访问 SageMaker 和 S3 资源。

```
┌─────────────────────────────────────────────────┐
│              用户登录 AWS Console               │
└─────────────────────────────────────────────────┘
                       │
                       ▼
              ┌───────────────┐
              │  MFA 已启用?  │
              └───────────────┘
               /           \
              /             \
           是 ✅            否 ❌
            │                │
            ▼                ▼
    ┌─────────────┐   ┌──────────────────────┐
    │ 正常使用    │   │ 只能进行以下操作:    │
    │ SageMaker   │   │ - 修改密码           │
    │ S3, ECR...  │   │ - 启用 MFA           │
    └─────────────┘   │ - 查看身份           │
                      └──────────────────────┘
```

**实现方式**: `DenyAllWithoutMFA` 使用 `NotAction` 排除自服务操作

**允许的无 MFA 操作**:
- `iam:CreateVirtualMFADevice` / `iam:EnableMFADevice` - 设置 MFA
- `iam:ChangePassword` / `iam:GetUser` - 密码管理
- `iam:GetAccountPasswordPolicy` - 查看密码策略
- `sts:GetCallerIdentity` - 验证身份

### 已实现的 Deny 控制

| Sid | 拒绝的操作 | 目的 |
|-----|-----------|------|
| `DenyAllWithoutMFA` | 未启用 MFA 时拒绝所有非自服务操作 | 强制 MFA |
| `DenyS3BucketListing` | `s3:ListAllMyBuckets` | 禁止浏览桶列表 |
| `DenyAccessToOtherBuckets` | 非公司桶的所有 S3 操作 | 强制桶隔离 |
| `DenyDangerousIAMActions` | IAM 策略创建/修改/删除 | 防止权限提升 |
| `DenySageMakerAdminActions` | Domain/UserProfile/Space 管理 | 防止越权管理，禁止用户自建 Space |
| `DenyPresignedUrlForOthersProfile` | 为他人 Profile 创建预签名 URL | 防止跨用户访问 Studio |
| `DenyS3BucketAdmin` | Bucket 创建/删除/策略修改 | 防止基础设施变更 |

### Studio 跨用户访问控制

防止用户 A 通过创建预签名 URL 进入用户 B 的 Studio 环境：

```
攻击路径（已阻止）:
┌─────────────────────────────────────────────────────────┐
│ 1. 用户 A 通过 AWS CLI 调用 ListUserProfiles            │
│ 2. 看到用户 B 的 Profile 名称                           │
│ 3. 调用 CreatePresignedDomainUrl(UserProfileName="B")   │
│ 4. ❌ DenyPresignedUrlForOthersProfile 阻止              │
│    (Owner 标签 != 当前 IAM 用户名)                       │
└─────────────────────────────────────────────────────────┘
```

**前提条件**: User Profile 必须有 `Owner` 标签，值为 IAM 用户名（创建脚本自动设置）
