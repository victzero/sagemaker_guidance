# IAM 资源说明

基于 `.env.example` 配置创建的所有 IAM 资源及其用途。

```
Company:   acme
IAM Path:  /acme-sagemaker/
```

---

## 1. Policies (11 个)

### 基础策略 (Base Policies)

| 策略名称                       | 用途                                                             |
| ------------------------------ | ---------------------------------------------------------------- |
| `SageMaker-Studio-Base-Access` | 所有用户的基础权限：查看 Domain、登录 Studio、访问自己的 Profile |
| `SageMaker-ReadOnly-Access`    | 只读权限：只能查看 SageMaker 资源和 S3 数据，不能修改            |
| `SageMaker-User-Boundary`      | 权限边界：限制用户最大权限，防止越权操作和权限提升               |

### 团队策略 (Team Policies)

| 策略名称                            | 用途                                                   |
| ----------------------------------- | ------------------------------------------------------ |
| `SageMaker-RiskControl-Team-Access` | Risk Control 团队的共享权限：访问团队级 Space 和 S3 桶 |
| `SageMaker-Algorithm-Team-Access`   | Algorithm 团队的共享权限：访问团队级 Space 和 S3 桶    |

### 项目策略 (Project Policies)

| 策略名称                                           | 用途                                                            |
| -------------------------------------------------- | --------------------------------------------------------------- |
| `SageMaker-RiskControl-FraudDetection-Access`      | Fraud Detection 项目成员权限：访问项目 Space、S3 数据、共享资产 |
| `SageMaker-RiskControl-AntiMoneyLaundering-Access` | AML 项目成员权限：访问项目 Space、S3 数据、共享资产             |
| `SageMaker-Algorithm-RecommendationEngine-Access`  | 推荐引擎项目成员权限：访问项目 Space、S3 数据、共享资产         |

### 执行角色策略 (Execution Policies)

| 策略名称                                                    | 用途                                                            |
| ----------------------------------------------------------- | --------------------------------------------------------------- |
| `SageMaker-RiskControl-FraudDetection-ExecutionPolicy`      | Fraud Detection 执行角色权限：训练任务访问 S3、写日志、拉取镜像 |
| `SageMaker-RiskControl-AntiMoneyLaundering-ExecutionPolicy` | AML 执行角色权限：训练任务访问 S3、写日志、拉取镜像             |
| `SageMaker-Algorithm-RecommendationEngine-ExecutionPolicy`  | 推荐引擎执行角色权限：训练任务访问 S3、写日志、拉取镜像         |

---

## 2. Groups (7 个)

### 平台级组 (Platform Groups)

| 组名称               | 用途                                              |
| -------------------- | ------------------------------------------------- |
| `sagemaker-admins`   | 管理员组：拥有 SageMaker 完整权限，可管理所有资源 |
| `sagemaker-readonly` | 只读组：只能查看资源，适用于审计、财务等角色      |

### 团队级组 (Team Groups)

| 组名称                   | 用途                                        |
| ------------------------ | ------------------------------------------- |
| `sagemaker-risk-control` | Risk Control 团队组：团队成员共享权限的基础 |
| `sagemaker-algorithm`    | Algorithm 团队组：团队成员共享权限的基础    |

### 项目级组 (Project Groups)

| 组名称                                 | 用途                                                        |
| -------------------------------------- | ----------------------------------------------------------- |
| `sagemaker-rc-fraud-detection`         | Fraud Detection 项目组：项目成员获得项目级 S3 和 Space 权限 |
| `sagemaker-rc-anti-money-laundering`   | AML 项目组：项目成员获得项目级 S3 和 Space 权限             |
| `sagemaker-algo-recommendation-engine` | 推荐引擎项目组：项目成员获得项目级 S3 和 Space 权限         |

---

## 3. Users (6 个)

### 管理员用户

| 用户名           | 角色       | 所属组             |
| ---------------- | ---------- | ------------------ |
| `sm-admin-jason` | 平台管理员 | `sagemaker-admins` |

### 团队用户

| 用户名          | 团队         | 项目                  | 所属组                                                          |
| --------------- | ------------ | --------------------- | --------------------------------------------------------------- |
| `sm-rc-alice`   | Risk Control | Fraud Detection       | `sagemaker-risk-control` + `sagemaker-rc-fraud-detection`       |
| `sm-rc-bob`     | Risk Control | Fraud Detection       | `sagemaker-risk-control` + `sagemaker-rc-fraud-detection`       |
| `sm-rc-carol`   | Risk Control | Anti Money Laundering | `sagemaker-risk-control` + `sagemaker-rc-anti-money-laundering` |
| `sm-algo-david` | Algorithm    | Recommendation Engine | `sagemaker-algorithm` + `sagemaker-algo-recommendation-engine`  |
| `sm-algo-eve`   | Algorithm    | Recommendation Engine | `sagemaker-algorithm` + `sagemaker-algo-recommendation-engine`  |

---

## 4. Execution Roles (3 个)

| 角色名称                                                  | 用途                                                              |
| --------------------------------------------------------- | ----------------------------------------------------------------- |
| `SageMaker-RiskControl-FraudDetection-ExecutionRole`      | Fraud Detection 训练/推理任务的服务角色，被 SageMaker 服务 assume |
| `SageMaker-RiskControl-AntiMoneyLaundering-ExecutionRole` | AML 训练/推理任务的服务角色，被 SageMaker 服务 assume             |
| `SageMaker-Algorithm-RecommendationEngine-ExecutionRole`  | 推荐引擎训练/推理任务的服务角色，被 SageMaker 服务 assume         |

---

## 权限继承关系

```
用户 (User)
  │
  ├── 加入 团队组 (Team Group)
  │     └── 绑定 Base-Access + Team-Access 策略
  │
  └── 加入 项目组 (Project Group)
        └── 绑定 Project-Access 策略
              └── 可以 PassRole 到 ExecutionRole
```

**示例**：`sm-rc-alice` 的权限来源：

| 来源                                  | 获得的策略                                                           |
| ------------------------------------- | -------------------------------------------------------------------- |
| 团队组 `sagemaker-risk-control`       | `SageMaker-Studio-Base-Access` + `SageMaker-RiskControl-Team-Access` |
| 项目组 `sagemaker-rc-fraud-detection` | `SageMaker-RiskControl-FraudDetection-Access`                        |
| 用户级别                              | Permissions Boundary: `SageMaker-User-Boundary`                      |

---

## 资源筛选命令

```bash
# 列出所有策略
aws iam list-policies --scope Local --path-prefix /acme-sagemaker/

# 列出所有组
aws iam list-groups --path-prefix /acme-sagemaker/

# 列出所有用户
aws iam list-users --path-prefix /acme-sagemaker/

# 列出所有角色
aws iam list-roles --path-prefix /acme-sagemaker/
```

---

## 命名规范总结

| 资源类型      | 命名格式                                     | 示例                                                   |
| ------------- | -------------------------------------------- | ------------------------------------------------------ |
| Policy (基础) | `SageMaker-{功能}-Access`                    | `SageMaker-Studio-Base-Access`                         |
| Policy (团队) | `SageMaker-{Team}-Team-Access`               | `SageMaker-RiskControl-Team-Access`                    |
| Policy (项目) | `SageMaker-{Team}-{Project}-Access`          | `SageMaker-RiskControl-FraudDetection-Access`          |
| Policy (执行) | `SageMaker-{Team}-{Project}-ExecutionPolicy` | `SageMaker-RiskControl-FraudDetection-ExecutionPolicy` |
| Group (平台)  | `sagemaker-{角色}`                           | `sagemaker-admins`                                     |
| Group (团队)  | `sagemaker-{team-fullname}`                  | `sagemaker-risk-control`                               |
| Group (项目)  | `sagemaker-{team}-{project}`                 | `sagemaker-rc-fraud-detection`                         |
| User (管理员) | `sm-admin-{name}`                            | `sm-admin-jason`                                       |
| User (团队)   | `sm-{team}-{name}`                           | `sm-rc-alice`                                          |
| Role          | `SageMaker-{Team}-{Project}-ExecutionRole`   | `SageMaker-RiskControl-FraudDetection-ExecutionRole`   |
