# IAM 资源说明

基于 `.env.shared` 配置创建的所有 IAM 资源及其用途。

> **更新日期**: 2025-01-05
>
> **设计版本**: 生产级 4 角色分离

```
Company:   acme
IAM Path:  /acme-sagemaker/
```

---

## 资源数量公式

| 资源类型     | 数量公式       | 说明                                        |
| ------------ | -------------- | ------------------------------------------- |
| IAM Groups   | 2 + T + P      | 2 平台组 + T 团队组 + P 项目组              |
| IAM Users    | A + U          | A 管理员 + U 普通用户                       |
| IAM Roles    | 1 + P×4        | 1 Domain 默认 + 每项目 4 角色               |
| IAM Policies | 7 + T + P×14   | 7 基础 + T 团队策略 + 每项目 14 策略        |

> **变量说明**：T = 团队数, P = 项目数, A = 管理员数, U = 普通用户数

**示例配置（2 团队 3 项目 6 用户）**：
- Groups: 2 + 2 + 3 = **7 个**
- Users: 1 + 5 = **6 个**
- Roles: 1 + 3×4 = **13 个**
- Policies: 7 + 2 + 3×14 = **51 个**

---

## 1. Policies（策略）

### 1.1 基础策略（7 个）

| 策略名称                          | 用途                                                   |
| --------------------------------- | ------------------------------------------------------ |
| `SageMaker-Studio-Base-Access`    | 所有用户基础权限：查看 Domain、登录 Studio             |
| `SageMaker-ReadOnly-Access`       | 只读权限：只能查看 SageMaker 和 S3 数据                |
| `SageMaker-User-Boundary`         | 权限边界：限制用户最大权限，防止越权和权限提升         |
| `SageMaker-User-SelfService`      | 自助服务：修改密码、设置 MFA（强制 MFA）               |
| `SageMaker-StudioAppPermissions`  | Studio 用户隔离：Private/Shared Space 权限控制         |
| `SageMaker-MLflowAppAccess`       | MLflow 实验追踪：创建/管理 MLflow App                  |
| `SageMaker-Shared-DenyAdmin`      | 禁止管理操作：拒绝创建 Domain/Space/Bucket（共享）     |

### 1.2 团队策略（每团队 1 个）

| 策略名称                            | 用途                                   |
| ----------------------------------- | -------------------------------------- |
| `SageMaker-RiskControl-Team-Access` | Risk Control 团队共享权限              |
| `SageMaker-Algorithm-Team-Access`   | Algorithm 团队共享权限                 |

### 1.3 项目策略（每项目 14 个）

**User Group 策略（3 个）**：

| 策略名称                                      | 用途                                |
| --------------------------------------------- | ----------------------------------- |
| `SageMaker-{Team}-{Project}-Access`           | 项目访问：Space、App 操作           |
| `SageMaker-{Team}-{Project}-S3Access`         | S3 共享策略（User 和 Role 共用）    |
| `SageMaker-{Team}-{Project}-PassRole`         | PassRole 共享策略（4 角色）         |

**ExecutionRole 策略（2 个，拆分设计）**：

| 策略名称                                          | 用途                                    |
| ------------------------------------------------- | --------------------------------------- |
| `SageMaker-{Team}-{Project}-ExecutionPolicy`      | ExecutionRole 基础：ECR、CloudWatch、VPC |
| `SageMaker-{Team}-{Project}-ExecutionJobPolicy`   | ExecutionRole 作业：PassRole、Jobs      |

**TrainingRole 策略（2 个，拆分设计）**：

| 策略名称                                          | 用途                                    |
| ------------------------------------------------- | --------------------------------------- |
| `SageMaker-{Team}-{Project}-TrainingPolicy`       | TrainingRole 基础：S3、ECR、CloudWatch  |
| `SageMaker-{Team}-{Project}-TrainingOpsPolicy`    | TrainingRole 操作：Training、Registry   |

**ProcessingRole 策略（2 个，拆分设计）**：

| 策略名称                                          | 用途                                    |
| ------------------------------------------------- | --------------------------------------- |
| `SageMaker-{Team}-{Project}-ProcessingPolicy`     | ProcessingRole 基础：S3、ECR、CloudWatch|
| `SageMaker-{Team}-{Project}-ProcessingOpsPolicy`  | ProcessingRole 操作：Glue、Athena       |

**InferenceRole 策略（2 个，拆分设计）**：

| 策略名称                                          | 用途                                    |
| ------------------------------------------------- | --------------------------------------- |
| `SageMaker-{Team}-{Project}-InferencePolicy`      | InferenceRole 基础：S3、ECR、CloudWatch |
| `SageMaker-{Team}-{Project}-InferenceOpsPolicy`   | InferenceRole 操作：Inference、Registry |

---

## 2. Groups（用户组）

### 2.1 平台级组（2 个）

| 组名称               | 用途                                              |
| -------------------- | ------------------------------------------------- |
| `sagemaker-admins`   | 管理员组：拥有 SageMaker 完整权限，可管理所有资源 |
| `sagemaker-readonly` | 只读组：只能查看资源，适用于审计、财务等角色      |

### 2.2 团队级组（每团队 1 个）

| 组名称                   | 用途                                        |
| ------------------------ | ------------------------------------------- |
| `sagemaker-risk-control` | Risk Control 团队组：团队成员共享权限的基础 |
| `sagemaker-algorithm`    | Algorithm 团队组：团队成员共享权限的基础    |

### 2.3 项目级组（每项目 1 个）

| 组名称                                 | 用途                                                        |
| -------------------------------------- | ----------------------------------------------------------- |
| `sagemaker-rc-fraud-detection`         | Fraud Detection 项目组：项目级 S3 和 PassRole 权限          |
| `sagemaker-rc-anti-money-laundering`   | AML 项目组：项目级 S3 和 PassRole 权限                      |
| `sagemaker-algo-recommendation-engine` | 推荐引擎项目组：项目级 S3 和 PassRole 权限                  |

---

## 3. Users（用户）

### 3.1 管理员用户

| 用户名           | 角色       | 所属组             |
| ---------------- | ---------- | ------------------ |
| `sm-admin-jason` | 平台管理员 | `sagemaker-admins` |

### 3.2 团队用户

| 用户名          | 团队         | 项目                  | 所属组                                                          |
| --------------- | ------------ | --------------------- | --------------------------------------------------------------- |
| `sm-rc-alice`   | Risk Control | Fraud Detection       | `sagemaker-risk-control` + `sagemaker-rc-fraud-detection`       |
| `sm-rc-bob`     | Risk Control | Fraud Detection       | `sagemaker-risk-control` + `sagemaker-rc-fraud-detection`       |
| `sm-rc-carol`   | Risk Control | Anti Money Laundering | `sagemaker-risk-control` + `sagemaker-rc-anti-money-laundering` |
| `sm-algo-david` | Algorithm    | Recommendation Engine | `sagemaker-algorithm` + `sagemaker-algo-recommendation-engine`  |
| `sm-algo-eve`   | Algorithm    | Recommendation Engine | `sagemaker-algorithm` + `sagemaker-algo-recommendation-engine`  |

---

## 4. Roles（执行角色）

### 4.1 Domain 默认角色（1 个）

| 角色名称                               | 用途                           |
| -------------------------------------- | ------------------------------ |
| `SageMaker-Domain-DefaultExecutionRole`| Domain 默认设置、回退角色      |

**附加策略**：
- `AmazonSageMakerFullAccess` (AWS 托管)
- `Canvas 策略组` (可选，默认开启)
- `SageMaker-StudioAppPermissions` (用户隔离)
- `SageMaker-MLflowAppAccess` (可选，默认开启)

### 4.2 项目角色（每项目 4 个）

| 角色类型       | 命名格式                                    | 用途                           |
| -------------- | ------------------------------------------- | ------------------------------ |
| ExecutionRole  | `SageMaker-{Team}-{Project}-ExecutionRole`  | Notebook/Studio 开发           |
| TrainingRole   | `SageMaker-{Team}-{Project}-TrainingRole`   | Training Jobs, HPO             |
| ProcessingRole | `SageMaker-{Team}-{Project}-ProcessingRole` | Processing Jobs, Data Wrangler |
| InferenceRole  | `SageMaker-{Team}-{Project}-InferenceRole`  | Endpoints, Batch Transform     |

**示例（Fraud Detection 项目）**：

| 角色名称                                                  | 用途           |
| --------------------------------------------------------- | -------------- |
| `SageMaker-RiskControl-FraudDetection-ExecutionRole`      | 开发角色       |
| `SageMaker-RiskControl-FraudDetection-TrainingRole`       | 训练角色       |
| `SageMaker-RiskControl-FraudDetection-ProcessingRole`     | 处理角色       |
| `SageMaker-RiskControl-FraudDetection-InferenceRole`      | 推理角色       |

---

## 5. 权限继承关系

```
用户 (User)
  │
  ├── 应用 Permissions Boundary
  │     └── SageMaker-User-Boundary (最大权限上限)
  │
  ├── 加入 团队组 (Team Group)
  │     └── 绑定: AmazonSageMakerFullAccess + Base + Team + SelfService
  │
  └── 加入 项目组 (Project Group)
        └── 绑定: Project + S3Access + PassRole + DenyAdmin

最终权限 = (Policy ∩ Boundary) - Deny
```

**示例**：`sm-rc-alice` 的权限来源：

| 来源                                  | 获得的策略                                     |
| ------------------------------------- | ---------------------------------------------- |
| Permissions Boundary                  | `SageMaker-User-Boundary` (权限上限)           |
| 团队组 `sagemaker-risk-control`       | `AmazonSageMakerFullAccess` + `Base` + `Team`  |
| 项目组 `sagemaker-rc-fraud-detection` | `Project` + `S3Access` + `PassRole`            |
| 项目组                                | `DenyAdmin` (显式拒绝)                         |

---

## 6. 资源筛选命令

```bash
# 列出所有策略
aws iam list-policies --scope Local --path-prefix /acme-sagemaker/

# 列出所有组
aws iam list-groups --path-prefix /acme-sagemaker/

# 列出所有用户
aws iam list-users --path-prefix /acme-sagemaker/

# 列出 Execution Roles（使用名称前缀，因为 Roles 使用默认路径 /）
aws iam list-roles --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ExecutionRole`)].RoleName'

# 列出 Training Roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `TrainingRole`)].RoleName'

# 列出 Processing Roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `ProcessingRole`)].RoleName'

# 列出 Inference Roles
aws iam list-roles --query 'Roles[?starts_with(RoleName, `SageMaker-`) && contains(RoleName, `InferenceRole`)].RoleName'
```

**注意**：Execution Role 使用默认路径 (`/`) 而非 IAM_PATH，以便 SageMaker 服务可以正确引用。

---

## 7. 命名规范总结

### IAM 资源命名

| 资源类型        | 命名格式                                     | 示例                                                   |
| --------------- | -------------------------------------------- | ------------------------------------------------------ |
| Policy (基础)   | `SageMaker-{功能}-Access`                    | `SageMaker-Studio-Base-Access`                         |
| Policy (团队)   | `SageMaker-{Team}-Team-Access`               | `SageMaker-RiskControl-Team-Access`                    |
| Policy (项目)   | `SageMaker-{Team}-{Project}-*`               | `SageMaker-RiskControl-FraudDetection-Access`          |
| Policy (角色)   | `SageMaker-{Team}-{Project}-{Role}Policy`    | `SageMaker-RiskControl-FraudDetection-ExecutionPolicy` |
| Group (平台)    | `sagemaker-{角色}`                           | `sagemaker-admins`                                     |
| Group (团队)    | `sagemaker-{team-fullname}`                  | `sagemaker-risk-control`                               |
| Group (项目)    | `sagemaker-{team}-{project}`                 | `sagemaker-rc-fraud-detection`                         |
| User (管理员)   | `sm-admin-{name}`                            | `sm-admin-jason`                                       |
| User (团队)     | `sm-{team}-{name}`                           | `sm-rc-alice`                                          |
| Role (默认)     | `SageMaker-Domain-DefaultExecutionRole`      | -                                                      |
| Role (项目)     | `SageMaker-{Team}-{Project}-{RoleType}`      | `SageMaker-RiskControl-FraudDetection-TrainingRole`    |

### 名称格式化函数 (`format_name`)

将 kebab-case 转为 PascalCase：

| 输入                    | 输出                  |
| ----------------------- | --------------------- |
| `risk-control`          | `RiskControl`         |
| `fraud-detection`       | `FraudDetection`      |
| `anti-money-laundering` | `AntiMoneyLaundering` |

---

## 8. 角色权限对比矩阵

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

---

> **完整规范**: 参见 [../CONVENTIONS.md](../CONVENTIONS.md) 和 [../../docs/02-iam-design.md](../../docs/02-iam-design.md)
