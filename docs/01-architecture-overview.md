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

> ⚠️ **重要**：本设计仅覆盖 **ML 实验与开发环境**，不包含生产推理部署。

| 范围         | 包含                             | 不包含              |
| ------------ | -------------------------------- | ------------------- |
| **环境定位** | 模型探索、特征工程、模型训练实验 | 生产级推理 Endpoint |
| **用户**     | 数据科学家、算法工程师           | 在线服务调用方      |
| **数据**     | 实验数据、训练数据               | 生产实时数据流      |
| **SLA**      | 开发环境级别                     | 生产高可用要求      |

**生产推理环境建议**：

- 使用独立 AWS 账号或完全隔离的 VPC
- 单独设计 IAM 角色和网络策略
- 配置生产级监控、告警和自动扩缩容

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
│   └── VPC Endpoints
│
├── 存储层
│   └── S3 Buckets (按项目隔离)
│
└── SageMaker 层
    ├── Domain (单一 Domain)
    ├── User Profiles (每用户一个)
    └── Spaces (每项目一个共享空间)
```

### 3.2 SageMaker 资源模型

```
SageMaker Domain (ml-platform-domain)
│
├── User Profiles
│   ├── profile-rc-alice    ──▶ IAM User: sm-rc-alice
│   ├── profile-rc-bob      ──▶ IAM User: sm-rc-bob
│   ├── profile-algo-frank  ──▶ IAM User: sm-algo-frank
│   └── ...
│
├── Shared Spaces (项目级共享)
│   ├── space-rc-project-a
│   │   └── Members: alice, bob, carol
│   ├── space-rc-project-b
│   │   └── Members: david, emma
│   ├── space-algo-project-x
│   │   └── Members: frank, grace, henry
│   └── ...
│
└── Private Spaces (可选，个人实验用)
    ├── private-alice
    ├── private-bob
    └── ...
```

---

## 4. 权限边界设计

### 4.1 权限层级

```
┌─────────────────────────────────────────────────────────────┐
│                    账号级边界                                 │
│  - 只能访问指定 VPC                                          │
│  - 只能访问指定 Region                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    团队级边界                                 │
│  - 风控团队只能访问 rc-* 资源                                 │
│  - 算法团队只能访问 algo-* 资源                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    项目级边界                                 │
│  - 只能访问所属项目的 S3 Bucket                               │
│  - 只能访问所属项目的 Shared Space                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    用户级边界                                 │
│  - 只能使用自己的 User Profile 登录                           │
│  - 只能启动自己的 Private Space                               │
└─────────────────────────────────────────────────────────────┘
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

| 文档                                            | 主要内容                                                            | 状态 |
| ----------------------------------------------- | ------------------------------------------------------------------- | ---- |
| [02-IAM 设计](./02-iam-design.md)               | Groups/Users/Roles/Policies、Policy JSON 模板、Permissions Boundary | ✅   |
| [03-VPC 网络](./03-vpc-network.md)              | VPCOnly 模式、Security Groups、VPC Endpoints 清单                   | ✅   |
| [04-S3 数据管理](./04-s3-data-management.md)    | Bucket 规划、Bucket Policy JSON、生命周期规则、SSE-S3/KMS 加密      | ✅   |
| [05-SageMaker Domain](./05-sagemaker-domain.md) | Domain 创建 CLI、Lifecycle Config 脚本、EFS 加密、自定义镜像        | ✅   |
| [06-User Profile](./06-user-profile.md)         | User Profile CLI、批量创建脚本、成员管理                            | ✅   |
| [07-Shared Space](./07-shared-space.md)         | Space 创建 CLI、存储监控、协作最佳实践                              | ✅   |
| [08-实施指南](./08-implementation-guide.md)     | 创建顺序 Checklist、验收用例                                        | ✅   |

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

### 8.2 可选配置（按需启用）

| 功能                         | 当前状态     | 建议                            |
| ---------------------------- | ------------ | ------------------------------- |
| Lifecycle Config（自动关闭） | **建议启用** | 成本控制关键，避免 GPU 空跑     |
| SSE-KMS 加密                 | 可选         | 无合规要求时 SSE-S3 足够        |
| 跨 Region 复制               | 可选         | 无灾备需求时不启用              |
| 自定义镜像                   | 可选         | 官方镜像满足大多数需求          |
| Permissions Boundary         | 可选         | 小团队可暂缓，IAM Policy 已足够 |
| CloudWatch 存储告警          | 可选         | 初期可手动监控                  |
| 用户自助门户                 | **不建议**   | 12-18 人规模，批量脚本足够      |

### 8.3 结论

建议实施路径：

1. **第一阶段**（必需）：VPC/IAM/S3/Domain/User Profile/Space
2. **第二阶段**（建议）：Lifecycle Config 成本控制
3. **第三阶段**（按需）：监控告警、高级安全配置

---

## 9. 参考资源

- [SageMaker Domain 文档](https://docs.aws.amazon.com/sagemaker/latest/dg/sm-domain.html)
- [SageMaker Studio Spaces](https://docs.aws.amazon.com/sagemaker/latest/dg/domain-space.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
