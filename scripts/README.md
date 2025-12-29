# SageMaker Platform Setup Scripts

AWS CLI 自动化脚本，用于部署 SageMaker ML 平台基础设施。

## 目录结构

```
scripts/
├── 01-iam/     # IAM 权限配置 (对应 docs/02-iam-design.md)
├── 02-vpc/     # VPC 网络配置 (对应 docs/03-vpc-network.md)
├── 03-s3/      # S3 数据管理 (对应 docs/04-s3-data-management.md)
└── README.md
```

## 执行顺序

**必须按顺序执行**，因为存在依赖关系：

```
01-iam  →  02-vpc  →  03-s3
  ↓          ↓          ↓
创建      创建      创建 Buckets
Policies   安全组    (需要 IAM Roles)
Groups    VPC       配置 Policies
Users     Endpoints  (需要 Execution Roles)
Roles
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
# IAM 模块无需额外配置（使用共享配置）
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
# S3 模块使用默认配置即可，如需自定义：
# cp .env.local.example .env.local
# vi .env.local  # 调整加密类型、Lifecycle 等

./setup-all.sh
./verify.sh
```

## 各步骤创建的资源

### 01-iam (IAM 权限)

| 资源类型     | 数量 | 说明                            |
| ------------ | ---- | ------------------------------- |
| IAM Policies | 8+   | Base, Team, Project, Execution  |
| IAM Groups   | 6+   | admins, readonly, team, project |
| IAM Users    | 10+  | admin + team members            |
| IAM Roles    | 4+   | SageMaker Execution Roles       |

### 02-vpc (VPC 网络)

| 资源类型        | 数量 | 说明                        |
| --------------- | ---- | --------------------------- |
| Security Groups | 2    | Studio, VPC Endpoints       |
| VPC Endpoints   | 7+   | SageMaker, STS, S3, Logs 等 |

### 03-s3 (S3 存储)

| 资源类型        | 数量 | 说明            |
| --------------- | ---- | --------------- |
| S3 Buckets      | 5    | 4 项目 + 1 共享 |
| Bucket Policies | 5    | 访问控制        |
| Lifecycle Rules | 5    | 自动清理和归档  |

## 环境变量配置

### 配置文件结构

```
scripts/
├── .env.shared.example   # 共享配置模板（提交 Git）
├── .env.shared           # 共享配置（不提交 Git）
├── common.sh             # 共享函数库
├── 01-iam/
│   └── .env.local.example  # IAM 特有配置模板
├── 02-vpc/
│   ├── .env.local.example  # VPC 特有配置模板
│   └── .env.local          # VPC 特有配置（必填）
└── 03-s3/
    └── .env.local.example  # S3 特有配置模板
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

| 模块   | 必填 | 特有变量                   |
| ------ | ---- | -------------------------- |
| 01-iam | ❌   | IAM_PATH                   |
| 02-vpc | ✅   | VPC_ID, VPC_CIDR, SUBNETs  |
| 03-s3  | ❌   | ENCRYPTION_TYPE, Lifecycle |

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

## 依赖关系图

```
                    ┌─────────────────┐
                    │   01-iam        │
                    │ (IAM Policies,  │
                    │  Groups, Users, │
                    │  Roles)         │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                              ▼
    ┌─────────────────┐            ┌─────────────────┐
    │   02-vpc        │            │   03-s3         │
    │ (Security       │            │ (Buckets need   │
    │  Groups,        │            │  Execution      │
    │  Endpoints)     │            │  Roles from     │
    └─────────────────┘            │  01-iam)        │
                                   └─────────────────┘
```

## 后续步骤

完成这三步后，继续：

1. **创建 SageMaker Domain** (docs/05-sagemaker-domain.md)
2. **创建 User Profiles** (docs/06-user-profile.md)
3. **创建 Shared Spaces** (docs/07-shared-space.md)

## 故障排除

### 权限不足

确保执行脚本的 IAM 用户/角色有足够权限：

- IAM: `IAMFullAccess` 或自定义策略
- VPC: `AmazonVPCFullAccess`
- S3: `AmazonS3FullAccess`

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
# 先清理 S3 (数据会丢失!)
cd 03-s3 && ./cleanup.sh

# 再清理 VPC
cd ../02-vpc && ./cleanup.sh

# 最后清理 IAM
cd ../01-iam && ./cleanup.sh
```
