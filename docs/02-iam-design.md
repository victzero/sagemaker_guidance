# 02 - IAM 权限设计

> 本文档描述 IAM Groups / Users / Roles / Policies 的设计

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符         | 说明              | 示例值                       |
| -------------- | ----------------- | ---------------------------- |
| `{company}`    | 公司/组织名称前缀 | `acme`                       |
| `{account-id}` | AWS 账号 ID       | `123456789012`               |
| `{region}`     | AWS 区域          | `ap-southeast-1`             |
| `{team}`       | 团队缩写          | `rc`（风控）、`algo`（算法） |
| `{project}`    | 项目名称          | `project-a`、`project-x`     |
| `{name}`       | 用户名            | `alice`、`frank`             |

**JSON 示例中的值**：

- `acme-sm-*` → 替换 `acme` 为您的公司前缀
- `arn:aws:iam::*:role/...` → 替换 `*` 为实际账号 ID
- `arn:aws:sagemaker:*:*:...` → 替换为实际 region 和账号 ID

---

## 1. IAM 资源概览

### 1.1 资源清单

| 类型         | 数量         | 说明                                   |
| ------------ | ------------ | -------------------------------------- |
| IAM Groups   | 2 + T + P    | 2 平台组 + T 团队组 + P 项目组         |
| IAM Users    | ~12-18       | 每项目 2-3 人                          |
| IAM Roles    | 1 + P×4      | 1 Domain 默认 + 每项目 4 个专用角色    |
| IAM Policies | 7 + T + P×14 | 7 基础 + T 团队策略 + 每项目 14 个策略 |

> **说明**：T = 团队数量，P = 项目数量
>
> **示例（2 团队 3 项目）**：Groups=7, Roles=13, Policies=51

### 1.2 设计原则

1. **最小权限**：只授予必要的权限
2. **职责分离**：管理员与开发者权限分开
3. **基于角色**：通过 Group 管理权限，避免直接给 User 授权
4. **可审计**：便于权限审计和变更追踪
5. **基础设施即代码（IaC）**：建议通过代码管理 IAM 资源

### 1.3 IaC 建议

> 💡 **建议**：IAM 资源**建议**通过 Infrastructure as Code 方式创建和管理，**不建议**在 AWS Console 手动操作。

| 建议           | 说明                                               |
| -------------- | -------------------------------------------------- |
| **工具选择**   | Terraform / AWS CDK / CloudFormation 任选其一      |
| **减少手动**   | 不建议通过 Console 创建 IAM User/Group/Role/Policy |
| **Tag 一致性** | 通过代码确保所有资源 Tag 正确且一致                |
| **版本控制**   | IaC 代码建议入 Git，变更可追溯                     |
| **审批流程**   | IAM 变更建议 Code Review 后再 Apply                |

**原因**：本设计依赖 IAM Policy 的 `Condition` 字段配合 Resource Tag 实现精细化访问控制（ABAC）。手动操作容易导致 Tag 遗漏或错误，可能造成用户无法登录或越权访问。

---

## 2. IAM Groups 设计

### 2.1 Group 层级

```
IAM Groups
│
├── 平台级
│   ├── sagemaker-admins          # 平台管理员
│   └── sagemaker-readonly        # 只读查看者
│
├── 团队级
│   ├── sagemaker-risk-control    # 风控团队（所有成员）
│   └── sagemaker-algorithm       # 算法团队（所有成员）
│
└── 项目级
    ├── sagemaker-rc-project-a    # 风控项目A
    ├── sagemaker-rc-project-b    # 风控项目B
    ├── sagemaker-algo-project-x  # 算法项目X
    └── sagemaker-algo-project-y  # 算法项目Y
```

### 2.2 Group 职责

| Group                        | 职责              | 典型权限              |
| ---------------------------- | ----------------- | --------------------- |
| `sagemaker-admins`           | Domain/Space 管理 | Full SageMaker Admin  |
| `sagemaker-readonly`         | 监控、审计        | Describe/List only    |
| `sagemaker-{team}`           | 团队通用权限      | Studio 登录、基础操作 |
| `sagemaker-{team}-{project}` | 项目数据访问      | 项目 S3 + Space 权限  |

### 2.3 用户 Group 关系

每个用户属于**多个 Group**（权限叠加）：

```
用户: sm-rc-alice
├── sagemaker-risk-control      # 团队组（基础权限）
└── sagemaker-rc-project-a      # 项目组（项目权限）

用户: sm-algo-frank
├── sagemaker-algorithm         # 团队组（基础权限）
└── sagemaker-algo-project-x    # 项目组（项目权限）
```

---

## 3. IAM Users 设计

### 3.1 User 命名规范

| 团队     | 命名模式          | 示例                         |
| -------- | ----------------- | ---------------------------- |
| 风控团队 | `sm-rc-{name}`    | sm-rc-alice, sm-rc-bob       |
| 算法团队 | `sm-algo-{name}`  | sm-algo-frank, sm-algo-grace |
| 管理员   | `sm-admin-{name}` | sm-admin-jason               |

### 3.2 User 属性配置

| 属性                | 配置    | 说明                 |
| ------------------- | ------- | -------------------- |
| Console Access      | ✅ 启用 | 需要登录 AWS Console |
| Programmatic Access | ⚠️ 按需 | API/CLI 访问         |
| MFA                 | ✅ 强制 | 安全要求             |
| Password Policy     | 强密码  | 遵循公司策略         |

### 3.3 User 清单模板

| User          | 团队 | 项目      | Groups                     |
| ------------- | ---- | --------- | -------------------------- |
| sm-rc-alice   | 风控 | project-a | risk-control, rc-project-a |
| sm-rc-bob     | 风控 | project-a | risk-control, rc-project-a |
| sm-rc-carol   | 风控 | project-a | risk-control, rc-project-a |
| sm-rc-david   | 风控 | project-b | risk-control, rc-project-b |
| sm-rc-emma    | 风控 | project-b | risk-control, rc-project-b |
| sm-algo-frank | 算法 | project-x | algorithm, algo-project-x  |
| sm-algo-grace | 算法 | project-x | algorithm, algo-project-x  |
| sm-algo-henry | 算法 | project-x | algorithm, algo-project-x  |
| sm-algo-ivy   | 算法 | project-y | algorithm, algo-project-y  |
| sm-algo-jack  | 算法 | project-y | algorithm, algo-project-y  |

---

## 4. IAM Roles 设计

### 4.1 Role 类型概览

| Role 类型           | 用途                           | 信任实体                | 数量        |
| ------------------- | ------------------------------ | ----------------------- | ----------- |
| **Domain Default**  | Domain 默认设置必需            | sagemaker.amazonaws.com | 1           |
| **ExecutionRole**   | Notebook/Studio 开发           | sagemaker.amazonaws.com | 每项目 1 个 |
| **TrainingRole**    | Training Jobs, HPO             | sagemaker.amazonaws.com | 每项目 1 个 |
| **ProcessingRole**  | Processing Jobs, Data Wrangler | sagemaker.amazonaws.com | 每项目 1 个 |
| **InferenceRole**   | Endpoints, Batch Transform     | sagemaker.amazonaws.com | 每项目 1 个 |
| Service-Linked Role | SageMaker 服务内部使用         | 自动创建                | -           |

### 4.2 Domain Default Execution Role（必须）

> ⚠️ **重要**：创建 SageMaker Domain 时，`DefaultUserSettings` 和 `DefaultSpaceSettings` 都**必须**指定 `ExecutionRole`。

```
SageMaker-Domain-DefaultExecutionRole
├── Trust: sagemaker.amazonaws.com
├── Policies:
│   ├── AmazonSageMakerFullAccess (AWS 托管)
│   ├── Canvas 策略组 (可选，默认开启)
│   ├── SageMaker-StudioAppPermissions (用户隔离)
│   └── SageMaker-MLflowAppAccess (实验追踪，可选)
└── 用途: Domain 默认设置、新建 User Profile/Space 时的回退角色
```

### 4.3 生产级 4 角色分离设计（推荐）

> 🔒 **最佳实践**：每个项目创建 4 个专用角色，实现职责分离和最小权限原则。

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       生产级 4 角色分离设计                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. ExecutionRole (开发/Notebook)                                           │
│     └── User Profile 绑定，Studio/Notebook 开发                             │
│     └── 权限：AmazonSageMakerFullAccess + 项目 S3/ECR                       │
│     └── Pass Role: 可以传递其他 3 个角色给作业                              │
│                                                                             │
│  2. TrainingRole (训练专用)                                                 │
│     └── Training Jobs, Hyperparameter Tuning                                │
│     └── 权限：训练数据读取 + 模型输出 + Model Registry 写入                 │
│                                                                             │
│  3. ProcessingRole (处理专用)                                               │
│     └── Processing Jobs, Data Wrangler                                      │
│     └── 权限：原始数据读取 + 处理输出 + Feature Store + Glue/Athena         │
│                                                                             │
│  4. InferenceRole (推理专用)                                                │
│     └── Endpoints, Batch Transform                                          │
│     └── 权限：模型只读 + 推理输出（最小权限）                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**IAM Roles 结构**：

```
IAM Roles
├── SageMaker-Domain-DefaultExecutionRole        # Domain 默认（必须）
│
├── Project: RiskControl / FraudDetection
│   ├── SageMaker-RiskControl-FraudDetection-ExecutionRole
│   ├── SageMaker-RiskControl-FraudDetection-TrainingRole
│   ├── SageMaker-RiskControl-FraudDetection-ProcessingRole
│   └── SageMaker-RiskControl-FraudDetection-InferenceRole
│
└── Project: Algorithm / Recommendation
    ├── SageMaker-Algorithm-Recommendation-ExecutionRole
    ├── SageMaker-Algorithm-Recommendation-TrainingRole
    ├── SageMaker-Algorithm-Recommendation-ProcessingRole
    └── SageMaker-Algorithm-Recommendation-InferenceRole
```

### 4.4 角色权限对比矩阵

| 权限类型                  | ExecutionRole | TrainingRole | ProcessingRole | InferenceRole |
| ------------------------- | :-----------: | :----------: | :------------: | :-----------: |
| AmazonSageMakerFullAccess |      ✅       |      ❌      |       ❌       |      ❌       |
| Canvas 策略组 (可选)      |      ✅       |      ❌      |       ❌       |      ❌       |
| StudioAppPermissions      |      ✅       |      ❌      |       ❌       |      ❌       |
| MLflowAppAccess (可选)    |      ✅       |      ❌      |       ❌       |      ❌       |
| S3 完整读写               |      ✅       |      ❌      |       ❌       |      ❌       |
| S3 训练数据/模型输出      |      ✅       |      ✅      |       ❌       |      ❌       |
| S3 原始数据/处理输出      |      ✅       |      ❌      |       ✅       |      ❌       |
| S3 模型只读/推理输出      |      ✅       |      ❌      |       ❌       |      ✅       |
| ECR 项目仓库读写          |      ✅       |      ❌      |       ❌       |      ❌       |
| ECR 只读                  |      ✅       |      ✅      |       ✅       |      ✅       |
| Training/HPO 操作         |      ✅       |      ✅      |       ❌       |      ❌       |
| Processing 操作           |      ✅       |      ❌      |       ✅       |      ❌       |
| Inference 操作            |      ✅       |      ❌      |       ❌       |      ✅       |
| Model Registry 写入       |      ✅       |      ✅      |       ❌       |      ❌       |
| Model Registry 只读       |      ✅       |      ✅      |       ❌       |      ✅       |
| Feature Store             |      ✅       |      ❌      |       ✅       |      ❌       |
| Glue/Athena               |      ❌       |      ❌      |       ✅       |      ❌       |
| Pass Role 到其他角色      |      ✅       |      ❌      |       ❌       |      ❌       |

### 4.5 使用场景

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

### 4.6 IAM Path 设计

> **重要设计决策**：Execution Role 使用默认路径 (`/`)，而非 IAM_PATH（如 `/acme-sagemaker/`）。

| 场景                   |   使用 IAM_PATH    |   使用默认路径    |
| ---------------------- | :----------------: | :---------------: |
| User Profile 绑定 Role |   ❌ 需完整 ARN    | ✅ 只需 Role 名称 |
| SageMaker AssumeRole   |    ❌ 可能失败     |    ✅ 自动识别    |
| 控制台查看             | ❌ 需手动指定 path |    ✅ 直接显示    |
| 其他 AWS 服务集成      |   ❌ 需完整 ARN    |    ✅ 兼容性好    |

**筛选方式**：通过名称前缀 `SageMaker-` 筛选各类角色。

### 4.7 Trust Policy（信任策略）

所有 Role 使用统一的 Trust Policy：

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

### 4.8 可选功能配置

| 功能            | 环境变量                 | 默认值 | 说明                            |
| --------------- | ------------------------ | ------ | ------------------------------- |
| Canvas 低代码   | `ENABLE_CANVAS`          | true   | SageMaker Canvas 低代码 ML 平台 |
| MLflow 追踪     | `ENABLE_MLFLOW`          | true   | MLflow 实验追踪                 |
| Training Role   | `ENABLE_TRAINING_ROLE`   | true   | 训练专用角色                    |
| Processing Role | `ENABLE_PROCESSING_ROLE` | true   | 处理专用角色                    |
| Inference Role  | `ENABLE_INFERENCE_ROLE`  | true   | 推理专用角色                    |

---

## 5. IAM Policies 设计

### 5.1 Policy 分层

```
IAM Policies
│
├── 基础层（7 个，所有用户通用）
│   ├── SageMaker-Studio-Base-Access        # 基础访问
│   ├── SageMaker-ReadOnly-Access           # 只读访问
│   ├── SageMaker-User-Boundary             # 权限边界
│   ├── SageMaker-User-SelfService          # 自助服务（密码、MFA）
│   ├── SageMaker-StudioAppPermissions      # Studio 用户隔离（安全必须）
│   ├── SageMaker-MLflowAppAccess           # MLflow 实验追踪
│   └── SageMaker-Shared-DenyAdmin          # 禁止管理操作（共享）
│
├── 团队层（每团队 1 个）
│   ├── SageMaker-RiskControl-Team-Access
│   └── SageMaker-Algorithm-Team-Access
│
├── 项目层（每项目 3 个 User 策略 + 共享策略）
│   ├── SageMaker-{Team}-{Project}-Access      # 项目访问
│   ├── SageMaker-{Team}-{Project}-S3Access    # S3 共享策略
│   └── SageMaker-{Team}-{Project}-PassRole    # PassRole 共享策略
│
└── 角色层（每项目 8 个，拆分设计避免 6KB 限制）
    ├── ExecutionPolicy + ExecutionJobPolicy   # 开发角色
    ├── TrainingPolicy + TrainingOpsPolicy     # 训练角色
    ├── ProcessingPolicy + ProcessingOpsPolicy # 处理角色
    └── InferencePolicy + InferenceOpsPolicy   # 推理角色
```

### 5.2 策略拆分设计

> ⚠️ **重要**：AWS IAM 策略有 6144 字节限制。每个 Role 的策略拆分为 **基础** + **操作** 两个策略。

| Role           | 基础策略 (S3/ECR/VPC) | 操作策略 (Jobs/Ops)   |
| -------------- | --------------------- | --------------------- |
| ExecutionRole  | `ExecutionPolicy`     | `ExecutionJobPolicy`  |
| TrainingRole   | `TrainingPolicy`      | `TrainingOpsPolicy`   |
| ProcessingRole | `ProcessingPolicy`    | `ProcessingOpsPolicy` |
| InferenceRole  | `InferencePolicy`     | `InferenceOpsPolicy`  |

**拆分原则**：

- **基础策略**: S3 访问、ECR 拉取、CloudWatch Logs、VPC 网络接口
- **操作策略**: 作业相关操作、PassRole、实验追踪、Model Registry 等

### 5.3 基础策略设计

**SageMaker-Studio-Base-Access** - 所有用户的基础权限：

```
允许操作:
- sagemaker:DescribeDomain
- sagemaker:DescribeUserProfile
- sagemaker:CreatePresignedDomainUrl
- sagemaker:ListSpaces
- sagemaker:DescribeSpace

条件:
- 仅限指定 Domain
```

**SageMaker-StudioAppPermissions** - Studio 用户隔离（安全必须）：

```
功能:
- 用户只能操作自己的 Private Space
- 可以在 Shared Space 创建/删除 App
- 只能为自己的 Profile 生成预签名 URL
- 防止用户误删他人资源

实现:
- sagemaker:OwnerUserProfileArn 条件
- sagemaker:ResourceTag/Owner 条件
```

**SageMaker-MLflowAppAccess** - MLflow 实验追踪（可选）：

```
功能:
- 创建/管理 MLflow App
- 记录参数、指标、模型版本
- 与 SageMaker Model Registry 集成
```

**SageMaker-Shared-DenyAdmin** - 禁止管理操作：

```
显式拒绝:
- sagemaker:CreateDomain / DeleteDomain
- sagemaker:CreateUserProfile / DeleteUserProfile
- sagemaker:CreateSpace / DeleteSpace / UpdateSpace
- s3:CreateBucket / DeleteBucket
```

### 5.4 团队策略设计

**SageMaker-{Team}-Team-Access** - 团队级权限：

```
允许操作:
- sagemaker:DescribeSpace
- sagemaker:ListApps
- s3:ListBucket (团队前缀)

条件:
- Resource Tag: team = {team}
```

### 5.5 项目策略设计

**SageMaker-{Team}-{Project}-Access** - 项目级权限：

```
允许操作:
- sagemaker:CreateApp
- sagemaker:DeleteApp
- sagemaker:DescribeApp

条件:
- Space: space-{team}-{project}
- sagemaker:ResourceTag/Project = {project}
```

**SageMaker-{Team}-{Project}-S3Access** - S3 共享策略（User 和 Role 共用）：

```
允许操作:
- s3:GetObject / PutObject / DeleteObject / ListBucket

资源范围:
- 项目桶: {company}-sm-{team}-{project}
- 共享桶: {company}-sm-shared-assets (只读)
- SageMaker 默认桶: sagemaker-{region}-{account-id}
```

**SageMaker-{Team}-{Project}-PassRole** - PassRole 共享策略：

```
允许操作:
- iam:PassRole

资源范围:
- SageMaker-{Team}-{Project}-ExecutionRole
- SageMaker-{Team}-{Project}-TrainingRole
- SageMaker-{Team}-{Project}-ProcessingRole
- SageMaker-{Team}-{Project}-InferenceRole

条件:
- iam:PassedToService = sagemaker.amazonaws.com
```

### 5.6 MFA 强制要求

> 🔐 **安全策略**：用户必须启用 MFA 才能访问 SageMaker 和 S3 资源。

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

### 5.7 Canvas 策略组（可选）

Canvas 是 SageMaker 的低代码 ML 平台。`ENABLE_CANVAS=true`（默认）时附加：

| 策略                                    | 用途                                       |
| --------------------------------------- | ------------------------------------------ |
| AmazonSageMakerCanvasFullAccess         | Canvas 核心功能                            |
| AmazonSageMakerCanvasAIServicesAccess   | AI 服务 (Bedrock, Textract, Comprehend 等) |
| AmazonSageMakerCanvasDataPrepFullAccess | 数据准备 (Data Wrangler, Glue, Athena)     |
| AmazonSageMakerCanvasDirectDeployAccess | 模型部署到 Endpoint (service-role 路径)    |

---

## 6. 权限绑定关系

### 6.1 Group-Policy 绑定

**平台级 Group**：

| Group              | 绑定 Policies                                         |
| ------------------ | ----------------------------------------------------- |
| sagemaker-admins   | AmazonSageMakerFullAccess, SageMaker-User-SelfService |
| sagemaker-readonly | SageMaker-ReadOnly-Access, SageMaker-User-SelfService |

**团队级 Group**：

| Group                  | 绑定 Policies                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| sagemaker-risk-control | AmazonSageMakerFullAccess, SageMaker-Studio-Base-Access, SageMaker-User-SelfService, Team-Access |
| sagemaker-algorithm    | AmazonSageMakerFullAccess, SageMaker-Studio-Base-Access, SageMaker-User-SelfService, Team-Access |

**项目级 Group**：

| Group                         | 绑定 Policies                                                  |
| ----------------------------- | -------------------------------------------------------------- |
| sagemaker-rc-fraud-detection  | Project-Access, SageMaker-Shared-DenyAdmin, S3Access, PassRole |
| sagemaker-algo-recommendation | Project-Access, SageMaker-Shared-DenyAdmin, S3Access, PassRole |

### 6.2 User-Group 绑定示例

```
sm-rc-alice:
  Groups:
    - sagemaker-risk-control      → AmazonSageMakerFullAccess + Base + Team Access
    - sagemaker-rc-fraud-detection → Project Access + S3 + PassRole + DenyAdmin

  最终权限 = SageMaker Full + Base + Team + Project S3 + PassRole
            - DenyAdmin (显式拒绝覆盖允许)
```

### 6.3 Execution Role 绑定（4 角色）

| ExecutionRole                                      | TrainingRole                                      | 用途          |
| -------------------------------------------------- | ------------------------------------------------- | ------------- |
| SageMaker-RiskControl-FraudDetection-ExecutionRole | SageMaker-RiskControl-FraudDetection-TrainingRole | Notebook/训练 |
| SageMaker-Algorithm-Recommendation-ExecutionRole   | SageMaker-Algorithm-Recommendation-TrainingRole   | Notebook/训练 |

| ProcessingRole                                      | InferenceRole                                      | 用途      |
| --------------------------------------------------- | -------------------------------------------------- | --------- |
| SageMaker-RiskControl-FraudDetection-ProcessingRole | SageMaker-RiskControl-FraudDetection-InferenceRole | 处理/推理 |
| SageMaker-Algorithm-Recommendation-ProcessingRole   | SageMaker-Algorithm-Recommendation-InferenceRole   | 处理/推理 |

### 6.4 User Profile 与 Execution Role 绑定

```
User Profile: profile-rc-fraud-alice
├── 绑定 ExecutionRole: SageMaker-RiskControl-FraudDetection-ExecutionRole
│   └── 可以 PassRole 到:
│       ├── TrainingRole   (训练作业)
│       ├── ProcessingRole (处理作业)
│       └── InferenceRole  (推理部署)
│
└── 可访问 S3:
    ├── acme-sm-rc-fraud-detection/* (读写)
    ├── acme-sm-shared-assets/* (只读)
    └── sagemaker-{region}-{account}/* (读写)
```

---

## 7. Policy JSON 模板

### 7.1 基础策略 - SageMaker-Studio-Base-Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDescribeDomain",
      "Effect": "Allow",
      "Action": ["sagemaker:DescribeDomain", "sagemaker:ListDomains"],
      "Resource": "arn:aws:sagemaker:*:*:domain/*"
    },
    {
      "Sid": "AllowListUserProfiles",
      "Effect": "Allow",
      "Action": [
        "sagemaker:ListUserProfiles",
        "sagemaker:ListSpaces",
        "sagemaker:ListApps"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowDescribeOwnProfile",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeUserProfile",
        "sagemaker:CreatePresignedDomainUrl"
      ],
      "Resource": "arn:aws:sagemaker:*:*:user-profile/*/*",
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Owner": "${aws:username}"
        }
      }
    }
  ]
}
```

### 7.2 项目策略 - SageMaker-RC-ProjectA-Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowProjectSpaceAccess",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeSpace",
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp",
        "sagemaker:DescribeApp"
      ],
      "Resource": [
        "arn:aws:sagemaker:*:*:space/*/space-rc-project-a",
        "arn:aws:sagemaker:*:*:app/*/*/*/*"
      ],
      "Condition": {
        "StringEquals": {
          "sagemaker:ResourceTag/Project": "project-a"
        }
      }
    },
    {
      "Sid": "AllowProjectS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-rc-project-a",
        "arn:aws:s3:::{company}-sm-rc-project-a/*"
      ]
    },
    {
      "Sid": "AllowSharedAssetsReadOnly",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::{company}-sm-shared-assets",
        "arn:aws:s3:::{company}-sm-shared-assets/*"
      ]
    }
  ]
}
```

**替换说明**：

| JSON 中的值          | 替换为                    |
| -------------------- | ------------------------- |
| `{company}`          | 公司名称前缀（如 `acme`） |
| `space-rc-project-a` | 实际 Space 名称           |
| `project-a`          | 实际项目标签值            |

### 7.3 Execution Role 策略 - SageMaker-RC-ProjectA-ExecutionPolicy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ProjectAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-rc-project-a",
        "arn:aws:s3:::{company}-sm-rc-project-a/*"
      ]
    },
    {
      "Sid": "AllowSharedAssetsReadOnly",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::{company}-sm-shared-assets",
        "arn:aws:s3:::{company}-sm-shared-assets/*"
      ]
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/sagemaker/*"
    },
    {
      "Sid": "AllowECRPull",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    }
  ]
}
```

---

## 8. iam:PassRole 权限配置

### 8.1 PassRole 概述

`iam:PassRole` 是一个特殊权限，允许用户将 IAM Role 传递给 AWS 服务（如 SageMaker）使用。

| 场景                | 传递的 Role    | 说明             |
| ------------------- | -------------- | ---------------- |
| 创建 User Profile   | ExecutionRole  | 绑定到 Profile   |
| 启动 Training Job   | TrainingRole   | 训练作业专用角色 |
| 启动 Processing Job | ProcessingRole | 处理作业专用角色 |
| 创建 Endpoint       | InferenceRole  | 推理部署专用角色 |

### 8.2 PassRole 策略设计（4 角色）

**原则**：用户只能 PassRole 自己项目的 4 个专用角色

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPassRoleToSageMaker",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole",
        "arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-TrainingRole",
        "arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ProcessingRole",
        "arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-InferenceRole"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "sagemaker.amazonaws.com"
        }
      }
    }
  ]
}
```

**替换说明**：

- `{account-id}` → 12 位 AWS 账号 ID
- `{Team}` → 团队名称 PascalCase（如 `RiskControl`）
- `{Project}` → 项目名称 PascalCase（如 `FraudDetection`）

### 8.3 PassRole 绑定关系（4 角色）

| 项目组                        | 可 PassRole 的 Roles（4 个）                               |
| ----------------------------- | ---------------------------------------------------------- |
| sagemaker-rc-fraud-detection  | ExecutionRole, TrainingRole, ProcessingRole, InferenceRole |
| sagemaker-algo-recommendation | ExecutionRole, TrainingRole, ProcessingRole, InferenceRole |

### 8.4 PassRole 调用链

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PassRole 调用链                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  IAM User (sm-rc-alice)                                                     │
│      │                                                                      │
│      ▼ PassRole                                                             │
│  ExecutionRole (绑定到 User Profile)                                        │
│      │                                                                      │
│      ├─► PassRole → TrainingRole   (提交训练作业)                           │
│      │                                                                      │
│      ├─► PassRole → ProcessingRole (提交处理作业)                           │
│      │                                                                      │
│      └─► PassRole → InferenceRole  (部署推理端点)                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 9. Permissions Boundary 设计

### 9.1 Boundary 概述

Permissions Boundary 是 IAM 的高级功能，用于限制 IAM 实体的最大权限范围。

| 用途             | 说明                                       |
| ---------------- | ------------------------------------------ |
| **防止权限提升** | 即使被授予 Admin 权限，也无法超出 Boundary |
| **委托管理**     | 允许团队管理自己的 IAM，但不能超出边界     |
| **合规要求**     | 满足安全审计的强制边界要求                 |

### 9.2 SageMaker 用户 Boundary

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSageMakerActions",
      "Effect": "Allow",
      "Action": [
        "sagemaker:Describe*",
        "sagemaker:List*",
        "sagemaker:CreatePresignedDomainUrl",
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3SageMakerBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-*",
        "arn:aws:s3:::{company}-sm-*/*"
      ]
    },
    {
      "Sid": "AllowCloudWatchReadOnly",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyIAMChanges",
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy",
        "iam:PutUserPermissionsBoundary",
        "iam:DeleteUserPermissionsBoundary"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyBoundaryModification",
      "Effect": "Deny",
      "Action": [
        "iam:DeletePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion"
      ],
      "Resource": "arn:aws:iam::*:policy/SageMaker-User-Boundary"
    }
  ]
}
```

### 9.3 Boundary 应用

| IAM 实体类型             | 应用的 Boundary                  |
| ------------------------ | -------------------------------- |
| 所有 SageMaker IAM Users | SageMaker-User-Boundary          |
| 所有 Execution Roles     | SageMaker-ExecutionRole-Boundary |

---

## 10. 权限审计配置

### 10.1 审计目标

| 目标         | 实现方式                         |
| ------------ | -------------------------------- |
| **操作追踪** | CloudTrail 记录所有 API 调用     |
| **权限分析** | IAM Access Analyzer 检测过宽权限 |
| **合规报告** | AWS Config 规则检测配置偏移      |

### 10.2 CloudTrail 配置

```
建议配置：
- 启用多区域 Trail
- S3 存储日志并启用加密
- 集成 CloudWatch Logs 实现实时告警
- 保留期限：至少 90 天
```

**关键事件监控**：

| 事件名称                   | 说明          | 告警级别 |
| -------------------------- | ------------- | -------- |
| `CreateUser`               | 创建 IAM 用户 | 中       |
| `AttachUserPolicy`         | 附加策略      | 中       |
| `CreateAccessKey`          | 创建访问密钥  | 高       |
| `ConsoleLogin`             | 控制台登录    | 低       |
| `CreatePresignedDomainUrl` | 进入 Studio   | 低       |

### 10.3 IAM Access Analyzer

建议配置规则：

| 检查项         | 说明                       |
| -------------- | -------------------------- |
| **外部访问**   | 检测资源是否被外部账号访问 |
| **未使用权限** | 识别 90 天未使用的权限     |
| **策略验证**   | 检测策略语法和最佳实践偏离 |

### 10.4 定期审计清单

| 频率       | 审计项                      |
| ---------- | --------------------------- |
| **每周**   | 检查新增 IAM 用户和权限变更 |
| **每月**   | 审查未使用的访问密钥和权限  |
| **每季度** | 全面权限审计，清理过期用户  |

### 10.5 告警配置示例

```
CloudWatch Alarm 建议：
1. IAM 策略变更 → SNS 通知管理员
2. 异常登录（非工作时间/异常 IP）→ 立即告警
3. 访问被拒绝次数异常 → 可能是攻击或配置错误
4. Execution Role 被非预期用户使用 → 安全调查
```

---

## 11. 检查清单

### 创建前检查

- [ ] 确认命名规范
- [ ] 确认团队和项目清单
- [ ] 确认人员名单
- [ ] 准备 Policy JSON 模板
- [ ] 确认 Permissions Boundary 策略

### 创建后验证

- [ ] 用户可以登录 Console
- [ ] 用户可以访问 SageMaker Studio
- [ ] 用户只能看到自己项目的 Space
- [ ] 用户只能访问自己项目的 S3 数据
- [ ] PassRole 权限验证通过
- [ ] CloudTrail 日志正常记录

---

## 12. IAM Domain 下"只能打开自己的 Profile"的可验证方案

> 目标：在 IAM 认证模式下，实现并可验收地证明——用户只能进入 Studio 的"自己的 User Profile"，并且只能在所属项目 Space 内工作。

### 12.1 设计思路（强制可验收）

- **原则**：不要求 UI 一定隐藏其他 Profile，但必须确保"打开/进入/创建 App"无法越权。
- **实现抓手**：
  - 将 `CreatePresignedDomainUrl`、`DescribeUserProfile`、`CreateApp/UpdateApp/DeleteApp` 作为关键控制点
  - 用 IAM Policy 对上述动作施加资源范围与条件约束（Owner/Project/Team 标签 + 命名规范）
- **资源标记**：
  - User Profile：`Owner=sm-<team>-<name>`、`Team`、`Project`
  - Space：`Team`、`Project`

### 12.2 可验收的测试用例（建议写入 UAT - User Acceptance Testing 用户验收测试）

- **用例 1：用户打开自己的 Profile**
  - 预期：成功进入 Studio；可启动/停止自己项目的 App；可访问自己项目 S3。
- **用例 2：用户尝试打开他人的 Profile**
  - 预期：失败（AccessDenied/无法进入）。
- **用例 3：用户尝试进入其他项目 Space 或创建 App**
  - 预期：失败（AccessDenied）。
- **用例 4：用户尝试访问其他项目 S3 Bucket**
  - 预期：失败（AccessDenied）。
- **用例 5：用户尝试选择超出平台允许的实例规格**
  - 预期：失败（AccessDenied 或 UI 不可选）。

### 12.3 实施建议（落地顺序）

- 先按项目建立 Execution Role（项目级），确保 S3 最小权限隔离可验收。
- 再用项目组（Group）聚合权限，避免对单个 User 直接授权导致漂移。
- 最后补齐"实例规格治理（白名单/上限）"与"Profile 打开权限"，并执行上述用例完成验收。
