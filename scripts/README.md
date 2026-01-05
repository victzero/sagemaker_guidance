# SageMaker Platform Setup Scripts

AWS CLI 自动化脚本，用于部署 SageMaker ML 平台基础设施。

## ✅ Phase 2 支持

**已启用 ML Jobs 功能**：脚本部署的 Execution Roles 已包含 `AmazonSageMakerFullAccess`，支持：

- ✅ **Processing Jobs** - 数据处理、特征工程
- ✅ **Training Jobs** - 模型训练、HPO
- ✅ **Inference Endpoints** - 实时推理、Serverless

详见文档：[docs/10-sagemaker-processing.md](../docs/10-sagemaker-processing.md) | [docs/12-sagemaker-training.md](../docs/12-sagemaker-training.md) | [docs/13-realtime-inference.md](../docs/13-realtime-inference.md)

## 目录结构

```
scripts/
├── 01-iam/              # IAM 权限配置 (对应 docs/02-iam-design.md)
├── 02-vpc/              # VPC 网络配置 (对应 docs/03-vpc-network.md)
├── 03-s3/               # S3 数据管理 (对应 docs/04-s3-data-management.md)
├── 04-sagemaker-domain/ # SageMaker Domain (对应 docs/05-sagemaker-domain.md)
├── 05-user-profiles/    # User Profiles + Private Spaces (对应 docs/06-user-profile.md)
│
│   ─────── Phase 2: 工作负载资源 (待实现) ───────
├── 07-ecr/              # ECR 仓库 (可选，自定义镜像需要)
├── 08-model-registry/   # Model Registry (模型版本管理)
├── 09-monitoring/       # 日志与监控配置
│
├── common.sh            # 共享函数库
├── .env.shared.example  # 共享配置模板
├── CONVENTIONS.md       # 开发规范
└── README.md
```

> **Note**: 使用 Private Space，每个 User Profile 对应一个 Private Space。
> Private Space 使用 User Profile 的项目级 Execution Role，可以访问项目 S3 桶。

## 执行顺序

**必须按顺序执行**，因为存在依赖关系：

```
Phase 1: 基础设施 (必需)
01-iam  →  02-vpc  →  03-s3  →  04-sagemaker-domain  →  05-user-profiles

Phase 2: 工作负载资源 (按需)
02-vpc/03-workload-sgs  →  07-ecr (可选)  →  08-model-registry
```

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Phase 1: 基础设施                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────────┐                                                │
│  │   01-iam        │  ← IAM Policies, Groups, Users, Roles          │
│  └────────┬────────┘                                                │
│           │                                                         │
│     ┌─────┴─────┐                                                   │
│     ▼           ▼                                                   │
│  ┌───────┐  ┌───────┐                                               │
│  │02-vpc │  │ 03-s3 │  ← Security Groups, Endpoints, Buckets        │
│  └───┬───┘  └───────┘                                               │
│      │                                                              │
│      ▼                                                              │
│  ┌─────────────────────┐                                            │
│  │ 04-sagemaker-domain │  ← Domain + Idle Shutdown                  │
│  └─────────┬───────────┘                                            │
│            │                                                        │
│            ▼                                                        │
│  ┌─────────────────────┐                                            │
│  │  05-user-profiles   │  ← User Profiles + Private Spaces          │
│  └─────────────────────┘                                            │
│                                                                     │
│  ✅ 完成后可进行交互式开发 (Studio Notebook)                        │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                     Phase 2: 工作负载资源 (按需)                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Phase 2A: 网络资源                                                 │
│  ┌─────────────────────────┐                                        │
│  │ 02-vpc/03-workload-sgs  │  ← Training/Processing/Inference SG    │
│  └─────────────────────────┘                                        │
│                                                                     │
│  Phase 2B: 容器镜像 (可选)     Phase 2C: 模型治理                   │
│  ┌─────────────────────────┐  ┌─────────────────────────┐          │
│  │       07-ecr            │  │   08-model-registry     │          │
│  │  (自定义镜像需要)       │  │   (模型版本管理)        │          │
│  └─────────────────────────┘  └─────────────────────────┘          │
│                                                                     │
│  Phase 2D: 日志与监控 (可选)                                        │
│  ┌─────────────────────────┐                                        │
│  │     09-monitoring       │  ← CloudWatch Logs/Alarms              │
│  └─────────────────────────┘                                        │
│                                                                     │
│  ✅ 完成后可运行 Processing/Training Jobs                           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## AWS Profile 配置

如果使用非默认的 AWS Profile，在执行脚本前先设置环境变量：

```bash
# 设置 AWS Profile (整个终端会话有效)
export AWS_PROFILE=tokyo

# 验证当前身份
aws sts get-caller-identity
```

## 快速开始

**推荐在 AWS CloudShell 中执行**（已预装 AWS CLI，无需配置凭证）

```bash
# ============================================
# Step 0: 配置共享环境变量（只需一次）
# ============================================
cp .env.shared.example .env.shared
vi .env.shared  # 填入 COMPANY, AWS_ACCOUNT_ID, TEAMS, PROJECTS, USERS 等

# ============================================
# Step 1: IAM 权限配置
# ============================================
cd 01-iam
./setup-all.sh   # 会显示预览，确认后执行
./verify.sh      # 验证

# ============================================
# Step 2: VPC 网络配置
# ============================================
cd ../02-vpc
cp .env.local.example .env.local
vi .env.local  # 填入 VPC_ID、SUBNET_IDs（必填）

./setup-all.sh
./verify.sh

# ============================================
# Step 3: S3 数据管理
# ============================================
cd ../03-s3
./setup-all.sh
./verify.sh

# ============================================
# Step 4: SageMaker Domain
# ============================================
cd ../04-sagemaker-domain
./check.sh       # 前置检查（推荐）
./setup-all.sh   # 创建 Domain + Lifecycle Config
./verify.sh

# ============================================
# Step 5: User Profiles
# ============================================
cd ../05-user-profiles
./setup-all.sh   # 为每个 IAM 用户创建 Profile
./verify.sh

# ============================================
# 完成！用户可以登录 Studio 使用 Private Space
# ============================================
```

## 各步骤创建的资源

### 01-iam (IAM 权限)

| 资源类型     | 数量 | 说明                                            |
| ------------ | ---- | ----------------------------------------------- |
| IAM Policies | 8+   | Base, Team, Project, Execution                  |
| IAM Groups   | 6+   | admins, readonly, team, project                 |
| IAM Users    | 10+  | admin + team members                            |
| IAM Roles    | 5+   | **Domain 默认角色** + 项目 Execution Roles      |

> ⚠️ **重要**：
> - `SageMaker-Domain-DefaultExecutionRole` 是创建 Domain 的必要前置条件
> - 所有 Execution Roles 已附加 `AmazonSageMakerFullAccess`，支持 Processing/Training/Inference

### 02-vpc (VPC 网络)

| 资源类型        | 数量 | 说明                        |
| --------------- | ---- | --------------------------- |
| Security Groups | 2    | Studio, VPC Endpoints       |
| VPC Endpoints   | 7+   | SageMaker, STS, S3, Logs 等 |

> **Phase 2A 补充**：`03-create-workload-sgs.sh` 会创建 Training/Processing/Inference 安全组

### 03-s3 (S3 存储)

| 资源类型        | 数量 | 说明            |
| --------------- | ---- | --------------- |
| S3 Buckets      | 5    | 4 项目 + 1 共享 |
| Bucket Policies | 5    | 访问控制        |
| Lifecycle Rules | 5    | 自动清理和归档  |

### 04-sagemaker-domain (SageMaker Domain)

| 资源类型         | 数量 | 说明                              |
| ---------------- | ---- | --------------------------------- |
| SageMaker Domain | 1    | VPCOnly + IAM 认证                |
| 内置 Idle Shutdown | - | 空闲自动关机（默认 60 分钟）      |

**特殊脚本**：
- `check.sh` - 前置检查和故障诊断（推荐在 setup 前运行）
- `check.sh --diagnose` - 诊断失败的 Domain
- `fix-execution-roles.sh` - 修复 Execution Role ARN 问题
- `fix-lifecycle-config.sh` - 移除自定义 LCC，启用内置 Idle Shutdown

### 05-user-profiles (User Profiles + Private Spaces)

| 资源类型       | 数量   | 说明                              |
| -------------- | ------ | --------------------------------- |
| User Profiles  | N      | 每个用户每项目一个                |
| Private Spaces | N      | 每个 Profile 对应一个 Space       |

> **命名格式**：
> - User Profile: `profile-{team}-{project}-{user}`
> - Private Space: `space-{team}-{project}-{user}`
>
> **示例**：用户 alice 参与两个项目会创建：
> - `profile-rc-fraud-alice` + `space-rc-fraud-alice`
> - `profile-rc-aml-alice` + `space-rc-aml-alice`

## 环境变量配置

### 配置文件结构

```
scripts/
├── .env.shared.example    # 共享配置模板（提交 Git）
├── .env.shared            # 共享配置（不提交 Git）
├── common.sh              # 共享函数库
├── 01-iam/
│   └── .env.local.example
├── 02-vpc/
│   ├── .env.local.example # VPC 特有配置模板
│   └── .env.local         # VPC 特有配置（必填）
├── 03-s3/
│   └── .env.local.example
├── 04-sagemaker-domain/
│   └── .env.local.example
└── 05-user-profiles/
    └── .env.local.example
```

### 共享配置 (.env.shared)

所有模块共享的核心变量：

| 变量             | 说明     | 示例                    |
| ---------------- | -------- | ----------------------- |
| `COMPANY`        | 公司前缀 | `acme`                  |
| `AWS_ACCOUNT_ID` | AWS 账号 | `123456789012`          |
| `AWS_REGION`     | AWS 区域 | `ap-southeast-1`        |
| `TEAMS`          | 团队列表 | `"rc algo"`             |
| `*_PROJECTS`     | 项目列表 | `"project-a project-b"` |
| `*_USERS`        | 用户列表 | `"alice bob"`           |

### 模块特有配置 (.env.local)

| 模块                | 必填 | 特有变量                          |
| ------------------- | ---- | --------------------------------- |
| 01-iam              | ❌   | IAM_PATH                          |
| 02-vpc              | ✅   | VPC_ID, VPC_CIDR, SUBNETs         |
| 03-s3               | ❌   | ENCRYPTION_TYPE, Lifecycle        |
| 04-sagemaker-domain | ❌   | DOMAIN_NAME, IDLE_TIMEOUT_MINUTES |
| 05-user-profiles    | ❌   | （使用共享配置）                  |

### 加载顺序

```bash
# common.sh 中 load_env() 加载顺序：
1. scripts/.env.shared           # 共享配置（必须）
2. scripts/{module}/.env.local   # 模块特有配置（可选）
3. scripts/{module}/.env         # 兼容旧配置（警告）
```

## 通用功能

所有脚本支持：

| 功能     | 命令             | 说明                                             |
| -------- | ---------------- | ------------------------------------------------ |
| **执行** | `./setup-all.sh` | 显示资源清单预览，确认后执行（幂等，可重复运行） |
| **验证** | `./verify.sh`    | 检查配置是否正确                                 |
| **清理** | `./cleanup.sh`   | 删除创建的资源                                   |

### setup-all.sh 资源预览模式

所有 `setup-all.sh` 脚本在执行前会**打印完整的资源清单**：

```
This script will create the following AWS XXX resources:

  Company:       acme
  Region:        ap-southeast-1
  ...

【资源类型 1】
  Team [rc - risk-control]:
    - resource-name-1
    - resource-name-2
  Total: N resources

【资源类型 2】
  ...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: X resources, Y policies, Z rules
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Filter resources later with:
  aws ... --filters ...

Do you want to proceed? [y/N]
```

这种模式确保用户在执行前清楚知道将创建哪些资源，避免意外操作。

## 开发规范

所有脚本遵循统一规范，详见 [CONVENTIONS.md](./CONVENTIONS.md)：

- Shell 脚本规范（Bash 4.x，`set -e` 安全）
- 环境变量命名规范
- IAM 资源命名规范
- 脚本目录结构

## 故障排除

### 权限不足

确保执行脚本的 IAM 用户/角色有足够权限：

- IAM: `IAMFullAccess` 或自定义策略
- VPC: `AmazonVPCFullAccess`
- S3: `AmazonS3FullAccess`
- SageMaker: `AmazonSageMakerFullAccess`

### 资源已存在

脚本设计为幂等，会跳过已存在的资源。如需重建，先运行 `cleanup.sh`。

### 验证失败

查看具体错误信息，检查：

- 环境变量是否正确
- AWS 凭证是否有效
- 依赖资源是否已创建

## 清理所有资源

**⚠️ 危险操作** - 按逆序清理：

```bash
# 1. 先清理 Spaces

# 2. 清理 User Profiles
cd ../05-user-profiles && ./cleanup.sh

# 3. 清理 SageMaker Domain (会删除 EFS!)
cd ../04-sagemaker-domain && ./cleanup.sh

# 4. 清理 S3 (数据会丢失!)
cd ../03-s3 && ./cleanup.sh

# 5. 清理 VPC
cd ../02-vpc && ./cleanup.sh

# 6. 最后清理 IAM
cd ../01-iam && ./cleanup.sh
```

## 用户登录流程

平台搭建完成后，用户按以下流程登录：

1. IAM User 登录 AWS Console
2. 导航到 SageMaker → Studio
3. 选择对应项目的 User Profile (`profile-{team}-{project}-{user}`)
4. 点击 "Open Studio"
5. 选择对应的 Private Space (`space-{team}-{project}-{user}`)
6. 点击 "Run" 启动 JupyterLab
7. 在 JupyterLab 中可以访问项目 S3 桶

> **多项目用户**：如果参与多个项目，需要切换 Profile 来访问不同项目的资源。
