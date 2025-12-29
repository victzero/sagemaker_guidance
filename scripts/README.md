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
# Step 1: IAM 权限配置
# ============================================
cd 01-iam
cp .env.example .env
vi .env  # 填入配置

./setup-all.sh   # 会显示预览，确认后执行
./verify.sh      # 验证

# ============================================
# Step 2: VPC 网络配置
# ============================================
cd ../02-vpc
cp .env.example .env
vi .env  # 填入 VPC ID、Subnet IDs 等

./setup-all.sh
./verify.sh

# ============================================
# Step 3: S3 数据管理
# ============================================
cd ../03-s3
cp .env.example .env
vi .env  # 确认公司名称、项目列表等

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

## 环境变量共享

各脚本共享以下核心变量，建议保持一致：

| 变量             | 说明     | 示例                    |
| ---------------- | -------- | ----------------------- |
| `COMPANY`        | 公司前缀 | `acme`                  |
| `AWS_ACCOUNT_ID` | AWS 账号 | `123456789012`          |
| `AWS_REGION`     | AWS 区域 | `ap-southeast-1`        |
| `TEAMS`          | 团队列表 | `"rc algo"`             |
| `RC_PROJECTS`    | 风控项目 | `"project-a project-b"` |
| `ALGO_PROJECTS`  | 算法项目 | `"project-x project-y"` |

## 通用功能

所有脚本支持：

| 功能     | 命令             | 说明                                     |
| -------- | ---------------- | ---------------------------------------- |
| **执行** | `./setup-all.sh` | 显示预览，确认后执行（幂等，可重复运行） |
| **验证** | `./verify.sh`    | 检查配置是否正确                         |
| **清理** | `./cleanup.sh`   | 删除创建的资源                           |

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
