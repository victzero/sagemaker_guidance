# 01 - 架构概览

> 本文档描述 SageMaker AI/ML 平台的整体架构设计

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符      | 说明              | 示例值                       |
| ----------- | ----------------- | ---------------------------- |
| `{company}` | 公司/组织名称前缀 | `acme`                       |
| `{team}`    | 团队缩写          | `rc`（风控）、`algo`（算法） |
| `{project}` | 项目名称          | `project-a`、`project-x`     |
| `{name}`    | 用户名            | `alice`、`frank`             |

---

## 0. 设计范围声明

> ⚠️ **重要**：本设计覆盖 **ML 实验与开发环境**，包含 Processing/Training/开发测试级 Inference。

| 范围         | 包含                                        | 不包含              |
| ------------ | ------------------------------------------- | ------------------- |
| **环境定位** | 模型探索、特征工程、模型训练、开发测试推理  | 生产级推理 Endpoint |
| **用户**     | 数据科学家、算法工程师                      | 在线服务调用方      |
| **数据**     | 实验数据、训练数据                          | 生产实时数据流      |
| **SLA**      | 开发环境级别                                | 生产高可用要求      |

**生产推理环境建议**：

- 使用独立 AWS 账号或完全隔离的 VPC
- 单独设计 IAM 角色和网络策略
- 配置生产级监控、告警和自动扩缩容

### 实施阶段划分

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            实施阶段                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  基础设施 (必需)                                                            │
│  ═══════════════                                                            │
│  IAM → VPC → S3 → Domain → User Profiles                                   │
│                                                                             │
│  工作负载资源 (按需)                                                        │
│  ═══════════════════                                                        │
│  • 工作负载安全组 (Processing/Training/Inference)                           │
│  • ECR 仓库 (自定义镜像需要)                                                │
│  • Model Registry (模型版本管理)                                            │
│  • 日志与监控                                                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. 设计目标

| 目标           | 说明                                |
| -------------- | ----------------------------------- |
| **团队隔离**   | 风控团队与算法团队资源隔离          |
| **项目隔离**   | 同一团队内不同项目数据隔离          |
| **协作共享**   | 同一项目内成员可共享 Notebook、数据 |
| **权限最小化** | 遵循最小权限原则                    |
| **可扩展**     | 支持后续团队/项目扩展               |

---

## 2. 团队与项目组织

### 2.1 组织结构

```
ML Platform
├── 风控团队 (risk-control)
│   ├── rc-project-a (风控项目A)
│   │   ├── user-rc-alice
│   │   ├── user-rc-bob
│   │   └── user-rc-carol
│   ├── rc-project-b (风控项目B)
│   │   ├── user-rc-david
│   │   └── user-rc-emma
│   └── rc-project-c (风控项目C) [可选]
│
└── 算法团队 (algorithm)
    ├── algo-project-x (算法项目X)
    │   ├── user-algo-frank
    │   ├── user-algo-grace
    │   └── user-algo-henry
    ├── algo-project-y (算法项目Y)
    │   ├── user-algo-ivy
    │   └── user-algo-jack
    └── algo-project-z (算法项目Z) [可选]
```

### 2.2 命名规范

| 资源类型         | 命名模式                                   | 示例                                           |
| ---------------- | ------------------------------------------ | ---------------------------------------------- |
| IAM Group (团队) | `sagemaker-{team}`                         | `sagemaker-risk-control`                       |
| IAM Group (项目) | `sagemaker-{team}-{project}`               | `sagemaker-risk-control-project-a`             |
| IAM User         | `sm-{team}-{name}`                         | `sm-rc-alice`                                  |
| IAM Role         | `SageMaker-{Team}-{Project}-ExecutionRole` | `SageMaker-RiskControl-ProjectA-ExecutionRole` |
| S3 Bucket        | `{company}-sm-{team}-{project}`            | `acme-sm-rc-project-a`                         |
| SageMaker Space  | `space-{team}-{project}`                   | `space-rc-project-a`                           |

---

## 3. 资源层级架构

### 3.1 AWS 资源层级

```
AWS Account
│
├── IAM 层
│   ├── IAM Groups (按团队 + 项目)
│   ├── IAM Users (开发人员)
│   ├── IAM Roles (SageMaker 执行角色)
│   └── IAM Policies (权限策略)
│
├── 网络层
│   ├── VPC (使用现有)
│   ├── Subnets (Private)
│   ├── Security Groups
│   │   ├── Studio SG (交互式开发)
│   │   ├── Training SG (训练任务)
│   │   ├── Processing SG (数据处理)
│   │   ├── Inference SG (推理服务)
│   │   └── VPC Endpoints SG
│   └── VPC Endpoints
│
├── 存储层
│   ├── S3 Buckets (按项目隔离)
│   └── ECR Repositories (按项目，可选)
│
├── SageMaker 层
│   ├── Domain (单一 Domain)
│   ├── User Profiles (每用户每项目一个)
│   ├── Private Spaces (每用户一个)
│   └── Model Registry (按项目)
│
└── 监控层 (可选)
    ├── CloudWatch Logs
    └── CloudWatch Alarms
```

### 3.2 SageMaker 资源模型

```
SageMaker Domain (ml-platform-domain)
│
├── User Profiles (每用户每项目一个)
│   │
│   │  用户 alice 参与两个项目:
│   ├── profile-rc-fraud-alice     ──▶ Execution Role: RC-Fraud-ExecutionRole
│   ├── profile-rc-aml-alice       ──▶ Execution Role: RC-AML-ExecutionRole
│   │
│   │  用户 bob 参与一个项目:
│   ├── profile-rc-fraud-bob       ──▶ Execution Role: RC-Fraud-ExecutionRole
│   │
│   │  用户 frank 参与一个项目:
│   └── profile-algo-rec-frank     ──▶ Execution Role: Algo-Rec-ExecutionRole
│
├── Private Spaces (每 Profile 一个)
│   ├── space-rc-fraud-alice       ──▶ 继承 profile-rc-fraud-alice 的 Role
│   ├── space-rc-aml-alice         ──▶ 继承 profile-rc-aml-alice 的 Role
│   ├── space-rc-fraud-bob         ──▶ 继承 profile-rc-fraud-bob 的 Role
│   └── space-algo-rec-frank       ──▶ 继承 profile-algo-rec-frank 的 Role
│
└── Model Registry (按项目)
    ├── rc-fraud-detection         ──▶ 模型版本管理
    ├── rc-anti-money-laundering
    └── algo-recommendation-engine
```

> 📌 **设计说明**：每个用户在每个参与的项目中有独立的 Profile + Space，确保项目间数据隔离。

---

## 4. 权限边界设计

### 4.1 权限层级

```
┌─────────────────────────────────────────────────────────────────┐
│                    账号级边界                                 │
│  - 只能访问指定 VPC                                          │
│  - 只能访问指定 Region                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    团队级边界                                 │
│  - 风控团队只能访问 rc-* 资源                                 │
│  - 算法团队只能访问 algo-* 资源                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    项目级边界                                 │
│  - 只能访问所属项目的 S3 Bucket                               │
│  - 只能访问所属项目的 Shared Space                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    用户级边界                                 │
│  - 只能使用自己的 User Profile 登录                           │
│  - 只能启动自己的 Private Space                               │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 访问控制矩阵

| 用户  | 所属团队 | 所属项目  | 可访问 Space         | 可访问 S3         |
| ----- | -------- | --------- | -------------------- | ----------------- |
| alice | 风控     | project-a | space-rc-project-a   | rc-project-a/\*   |
| bob   | 风控     | project-a | space-rc-project-a   | rc-project-a/\*   |
| david | 风控     | project-b | space-rc-project-b   | rc-project-b/\*   |
| frank | 算法     | project-x | space-algo-project-x | algo-project-x/\* |

---

## 5. 网络架构

### 5.1 VPC 模式选择

| 模式            | 说明                      | 本项目选择 |
| --------------- | ------------------------- | ---------- |
| Public Internet | Studio 通过 Internet 访问 | ❌         |
| VPC Only        | Studio 完全在 VPC 内      | ✅         |

### 5.2 网络拓扑

```
┌─────────────────────────────────────────────────────────────┐
│                       现有 VPC                               │
│                                                              │
│  ┌────────────────────┐    ┌────────────────────┐          │
│  │  Private Subnet A  │    │  Private Subnet B  │          │
│  │    (AZ: ap-xx-1a)  │    │    (AZ: ap-xx-1b)  │          │
│  │                    │    │                    │          │
│  │  ┌──────────────┐  │    │  ┌──────────────┐  │          │
│  │  │ SageMaker    │  │    │  │ SageMaker    │  │          │
│  │  │ Studio ENI   │  │    │  │ Studio ENI   │  │          │
│  │  └──────────────┘  │    │  └──────────────┘  │          │
│  └────────────────────┘    └────────────────────┘          │
│              │                        │                     │
│              └────────┬───────────────┘                     │
│                       │                                      │
│              ┌────────▼────────┐                            │
│              │  Security Group │                            │
│              │  (SageMaker)    │                            │
│              └────────┬────────┘                            │
│                       │                                      │
│  ┌────────────────────▼────────────────────────────────┐   │
│  │              VPC Endpoints                           │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐  │   │
│  │  │ S3 GW    │ │SageMaker │ │SageMaker │ │  STS   │  │   │
│  │  │ Endpoint │ │ API      │ │ Runtime  │ │Endpoint│  │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. 数据流设计

### 6.1 数据访问路径

```
开发人员 (IAM User)
       │
       │ 1. AWS Console 登录
       ▼
SageMaker Studio
       │
       │ 2. 选择 User Profile
       ▼
Notebook (在 Space 中)
       │
       │ 3. 通过 Execution Role 访问
       ▼
S3 Bucket (项目数据)
```

### 6.2 数据隔离策略

| 层级            | 隔离方式 | 实现机制                          |
| --------------- | -------- | --------------------------------- |
| 团队间          | 硬隔离   | S3 Bucket Policy + IAM Policy     |
| 项目间          | 硬隔离   | S3 Prefix Policy + IAM Conditions |
| 用户间 (同项目) | 共享     | 同一 Execution Role               |

---

## 7. 详细文档索引

> ✅ 所有设计文档已完善，以下为详细配置指引。

### 基础设施

| 文档                                            | 主要内容                                                            | 状态 |
| ----------------------------------------------- | ------------------------------------------------------------------- | ---- |
| [02-IAM 设计](./02-iam-design.md)               | Groups/Users/Roles/Policies、Policy JSON 模板、Permissions Boundary | ✅   |
| [03-VPC 网络](./03-vpc-network.md)              | VPCOnly 模式、Security Groups、VPC Endpoints 清单                   | ✅   |
| [04-S3 数据管理](./04-s3-data-management.md)    | Bucket 规划、Bucket Policy JSON、生命周期规则、SSE-S3/KMS 加密      | ✅   |
| [05-SageMaker Domain](./05-sagemaker-domain.md) | Domain 创建 CLI、内置 Idle Shutdown、EFS 加密                       | ✅   |
| [06-User Profile](./06-user-profile.md)         | User Profile + Private Space 创建、多项目用户架构                   | ✅   |
| [08-实施指南](./08-implementation-guide.md)     | 创建顺序 Checklist、验收用例                                        | ✅   |

### 工作负载资源

| 文档                                                     | 主要内容                                              | 状态 |
| -------------------------------------------------------- | ----------------------------------------------------- | ---- |
| [14-工作负载资源设计](./14-workload-resources.md)        | Security Groups、ECR、Model Registry、KMS、日志规划   | ✅   |
| [15-工作负载实施计划](./15-workload-implementation.md)   | 详细实施步骤、时间表、回滚方案                        | ✅   |

### ML 服务快速入门

| 文档                                                | 主要内容                                      | 状态 |
| --------------------------------------------------- | --------------------------------------------- | ---- |
| [10-Processing 数据处理](./10-sagemaker-processing.md) | SKLearn/Spark Processing、数据路径规范        | ✅   |
| [11-Data Wrangler](./11-data-wrangler.md)           | 可视化数据准备                                | ✅   |
| [12-Training 模型训练](./12-sagemaker-training.md)  | XGBoost/SKLearn 训练、HPO、Spot 实例          | ✅   |
| [13-Inference 实时推理](./13-realtime-inference.md) | Serverless/Real-Time Endpoint、Batch Transform | ✅   |

---

## 8. 设计复杂度评估

> 📌 针对 **12-18 人**、**4 个项目** 规模的评估。

### 8.1 核心设计（必需）

| 组件                  | 复杂度 | 说明                                    |
| --------------------- | ------ | --------------------------------------- |
| 单一 Domain           | 低     | 最简架构，避免多 Domain 管理复杂性      |
| 按项目 S3 Bucket      | 低     | 4 个 Bucket，权限清晰，优于 Prefix 方案 |
| 按项目 IAM Group      | 低     | 4 个 Group，成员管理简单                |
| VPCOnly + Endpoints   | 中     | 必要的网络隔离，一次性配置              |
| 按项目 Execution Role | 低     | 4 个 Role，权限边界清晰                 |
| 内置 Idle Shutdown    | 低     | Domain 级别配置，自动生效               |

### 8.2 工作负载资源（按需）

| 组件                  | 复杂度 | 优先级 | 说明                                    |
| --------------------- | ------ | ------ | --------------------------------------- |
| 工作负载安全组        | 低     | 🔴 高  | Training/Processing/Inference 分离     |
| Model Registry        | 低     | 🔴 高  | 模型版本管理必需                        |
| ECR 仓库              | 中     | 🟡 中  | 仅自定义镜像需要                        |
| CloudWatch 日志保留   | 低     | 🟢 低  | 可后续配置                              |
| KMS 密钥              | 中     | 🟢 低  | 高安全需求时启用                        |

### 8.3 可选配置

| 功能                         | 当前状态     | 建议                            |
| ---------------------------- | ------------ | ------------------------------- |
| SSE-KMS 加密                 | 可选         | 无合规要求时 SSE-S3 足够        |
| 跨 Region 复制               | 可选         | 无灾备需求时不启用              |
| Permissions Boundary         | 可选         | 小团队可暂缓，IAM Policy 已足够 |
| CloudWatch 告警              | 可选         | 初期可手动监控                  |
| 用户自助门户                 | **不建议**   | 12-18 人规模，批量脚本足够      |

### 8.4 建议实施路径

```
基础设施 (必需，约 2 天):
├── IAM → VPC → S3 → Domain → User Profiles
└── 完成后可进行交互式开发 (Studio Notebook)

网络资源 (建议，约 0.5 天):
├── 创建工作负载安全组
└── 完成后可运行 Processing/Training Jobs

模型治理 (建议，约 0.5 天):
├── 创建 Model Registry
└── 完成后可进行模型版本管理

按需配置:
├── ECR 仓库 (自定义镜像)
└── 日志与监控配置
```

---

## 9. 参考资源

- [SageMaker Domain 文档](https://docs.aws.amazon.com/sagemaker/latest/dg/sm-domain.html)
- [SageMaker Studio Spaces](https://docs.aws.amazon.com/sagemaker/latest/dg/domain-space.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
