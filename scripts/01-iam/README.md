# SageMaker IAM Setup Scripts

基于 [02-iam-design.md](../../docs/02-iam-design.md) 设计文档的 AWS CLI 自动化脚本。

> **运行环境**: AWS CloudShell (Amazon Linux 2, Bash 4.x+)
>
> **开发规范**: 参见 [../CONVENTIONS.md](../CONVENTIONS.md)

## 快速开始

```bash
# 1. 配置共享环境变量（首次运行）
cd ../
cp .env.shared.example .env.shared
vi .env.shared  # 填入 COMPANY, AWS_ACCOUNT_ID, TEAMS, USERS 等

# 2. 配置 IAM 特有变量（可选，通常使用默认值）
cd 01-iam/
cp .env.local.example .env.local
vi .env.local  # 可修改 PASSWORD_PREFIX/SUFFIX, ENABLE_CONSOLE_LOGIN

# 3. 执行创建（会显示预览，确认后执行）
./setup-all.sh

# 4. 验证配置
./verify.sh
```

## 目录结构

```
scripts/
├── .env.shared.example   # 共享环境变量模板
├── .env.shared           # 共享环境变量 (不提交到 Git)
│
└── 01-iam/
    ├── .env.local.example    # IAM 特有变量模板 (可选)
    ├── .env.local            # IAM 特有变量 (不提交到 Git)
    │
    ├── policies/             # 策略模板文件 (与脚本分离)
    │   ├── README.md
    │   ├── trust-policy-sagemaker.json  # Trust Policy (静态)
    │   ├── base-access.json.tpl
    │   ├── team-access.json.tpl
    │   ├── project-access.json.tpl
    │   ├── execution-role.json.tpl
    │   ├── user-boundary.json.tpl
    │   ├── readonly.json.tpl
    │   ├── self-service.json.tpl
    │   ├── studio-app-permissions.json.tpl  # Studio 用户隔离
    │   └── mlflow-app-access.json.tpl       # MLflow 实验追踪
    │
    ├── 00-init.sh           # 初始化和工具函数
    ├── 01-create-policies.sh # 创建 IAM Policies
    ├── 02-create-groups.sh  # 创建 IAM Groups
    ├── 03-create-users.sh   # 创建 IAM Users
    ├── 04-create-roles.sh   # 创建 Execution Roles
    ├── 05-bind-policies.sh  # 绑定 Policies 到 Groups
    ├── 06-add-users-to-groups.sh # 添加 Users 到 Groups
    ├── setup-all.sh         # 主控脚本 (顺序执行所有步骤)
    ├── verify.sh            # 验证配置
    ├── cleanup.sh           # 清理资源 (危险!)
    ├── output/              # 生成的策略 JSON 和凭证文件
    │   ├── policy-*.json
    │   └── user-credentials.txt
    └── README.md
```

## 架构设计

### 多团队/项目组织结构

```
Company (acme)
│
├── Team: risk-control (rc)
│   ├── Project: fraud-detection
│   │   └── Users: alice, bob
│   └── Project: anti-money-laundering
│       └── Users: charlie
│
└── Team: algorithm (algo)
    └── Project: recommendation
        └── Users: david, eve
```

**命名约定**:

| 资源类型         | 命名规则                                   | 示例                                                 |
| ---------------- | ------------------------------------------ | ---------------------------------------------------- |
| IAM User         | `sm-{team}-{username}`                     | `sm-rc-alice`                                        |
| IAM Group (团队) | `sagemaker-{team-fullname}`                | `sagemaker-risk-control`                             |
| IAM Group (项目) | `sagemaker-{team}-{project}`               | `sagemaker-rc-fraud-detection`                       |
| Execution Role   | `SageMaker-{Team}-{Project}-ExecutionRole` | `SageMaker-RiskControl-FraudDetection-ExecutionRole` |
| S3 Bucket        | `{company}-sm-{team}-{project}`            | `acme-sm-rc-fraud-detection`                         |

### 项目级 S3 隔离架构

```
S3 Buckets
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

项目桶 (完全隔离):
┌────────────────────────────────┐
│ acme-sm-rc-fraud-detection     │ ← rc/fraud-detection 专用
├────────────────────────────────┤
│ acme-sm-rc-anti-money-launder  │ ← rc/aml 专用
├────────────────────────────────┤
│ acme-sm-algo-recommendation    │ ← algo/recommendation 专用
└────────────────────────────────┘

共享桶 (只读):
┌────────────────────────────────┐
│ acme-sm-shared-assets          │ ← 所有项目可读取
│   ├── datasets/                │   公共数据集
│   ├── models/                  │   预训练模型
│   └── scripts/                 │   共享脚本
└────────────────────────────────┘

SageMaker 默认桶:
┌────────────────────────────────┐
│ sagemaker-{region}-{account}   │ ← ML 作业自动使用
└────────────────────────────────┘
```

### IAM 多层权限控制

```
┌─────────────────────────────────────────────────────────────┐
│                    IAM 多层权限控制架构                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌─────────────┐                                          │
│   │  IAM User   │ ← Permissions Boundary (最大权限边界)     │
│   └──────┬──────┘                                          │
│          │                                                  │
│          ▼                                                  │
│   ┌─────────────┐                                          │
│   │  IAM Group  │ ← 团队组 + 项目组 (双重归属)              │
│   └──────┬──────┘                                          │
│          │                                                  │
│          ▼                                                  │
│   ┌─────────────┐                                          │
│   │User Profile │ ← 绑定 Project Execution Role            │
│   └──────┬──────┘                                          │
│          │                                                  │
│          ▼                                                  │
│   ┌─────────────┐                                          │
│   │Execution Role│ ← 项目级 S3/ECR 权限                    │
│   └─────────────┘                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 权限绑定关系

```
                           ┌─────────────────────────────────┐
                           │      IAM User: sm-rc-alice      │
                           └───────────────┬─────────────────┘
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    │                      │                      │
                    ▼                      ▼                      ▼
        ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
        │ Permissions       │  │ Team Group        │  │ Project Group     │
        │ Boundary          │  │ sagemaker-rc      │  │ sagemaker-rc-     │
        │                   │  │                   │  │ fraud-detection   │
        └───────────────────┘  └───────────────────┘  └───────────────────┘
                │                      │                      │
                │                      │                      │
                ▼                      ▼                      ▼
        ┌───────────────────────────────────────────────────────────────┐
        │                     有效权限 = 三者交集                        │
        │  • 只能访问 rc 团队的 S3 桶前缀                                │
        │  • 只能访问 fraud-detection 项目的资源                        │
        │  • 不能执行 IAM/Domain 管理操作                               │
        └───────────────────────────────────────────────────────────────┘
```

### Execution Role 项目隔离

```
User Profile                          Execution Role
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

sm-rc-alice-profile    ──bindTo──►   SageMaker-RiskControl-
                                     FraudDetection-ExecutionRole
                                           │
                                           ▼
                                     ┌─────────────────────┐
                                     │ 项目 S3 权限:       │
                                     │ acme-sm-rc-fraud-*  │
                                     │                     │
                                     │ 共享资产 (只读):    │
                                     │ acme-sm-shared-*    │
                                     │                     │
                                     │ ECR (项目隔离):     │
                                     │ acme-sm-rc-fraud-*  │
                                     └─────────────────────┘
```

**关键点**:

- 每个项目有独立的 Execution Role
- Execution Role 的 S3 权限**硬编码**到项目桶
- User Profile 绑定项目 Execution Role，**不是** Domain 默认 Role

### 权限层次总结

| 层次                      | 控制内容                    | 隔离粒度 |
| ------------------------- | --------------------------- | -------- |
| **Permissions Boundary**  | 最大权限上限，禁止危险操作  | 全局     |
| **Team Group Policy**     | 团队级 S3 桶前缀访问        | 团队     |
| **Project Group Policy**  | 项目 Space 访问、项目 S3 桶 | 项目     |
| **Execution Role Policy** | ML 作业的 S3/ECR 访问       | 项目     |

### 访问矩阵示例

| 用户             | fraud-detection S3 | aml S3  | recommendation S3 | shared-assets |
| ---------------- | :----------------: | :-----: | :---------------: | :-----------: |
| alice (rc/fraud) |      ✅ 读写       |   ❌    |        ❌         |    ✅ 只读    |
| charlie (rc/aml) |         ❌         | ✅ 读写 |        ❌         |    ✅ 只读    |
| david (algo/rec) |         ❌         |   ❌    |      ✅ 读写      |    ✅ 只读    |

### 与控制台创建的区别

| 方面           | 控制台快速设置       | 我们的设计                             |
| -------------- | -------------------- | -------------------------------------- |
| S3 权限        | 通配符 `sagemaker-*` | 项目桶 `{company}-sm-{team}-{project}` |
| 隔离粒度       | 无隔离               | 团队 → 项目 → 用户                     |
| Execution Role | 所有用户共用一个     | 每个项目独立 Role                      |
| 扩展性         | 手动管理             | 脚本化，加项目只需改 .env              |

## 环境变量说明

详细配置示例见 `.env.example`，关键变量：

| 变量                       | 说明                    | 示例                     |
| -------------------------- | ----------------------- | ------------------------ |
| `COMPANY`                  | 公司/组织前缀           | `acme`                   |
| `AWS_ACCOUNT_ID`           | AWS 账号 ID             | `123456789012`           |
| `AWS_REGION`               | AWS 区域                | `ap-southeast-1`         |
| `IAM_PATH`                 | IAM 资源路径 (自动设置) | `/${COMPANY}-sagemaker/` |
| `TEAMS`                    | 团队列表                | `"rc algo"`              |
| `TEAM_RC_FULLNAME`         | 团队全称                | `risk-control`           |
| `RC_PROJECTS`              | 团队项目                | `"fraud-detection"`      |
| `RC_FRAUD_DETECTION_USERS` | 项目用户                | `"alice bob"`            |
| `ENABLE_CONSOLE_LOGIN`     | 启用 Console 登录       | `false` (默认)           |
| `ENABLE_CANVAS`            | 启用 Canvas 低代码 ML   | `true` (默认)            |
| `ENABLE_MLFLOW`            | 启用 MLflow 实验追踪    | `true` (默认)            |

## Console 登录控制

默认情况下，用户**不能**登录 AWS Console，只能通过 API 访问：

```bash
# 禁用 Console 登录（默认）
./03-create-users.sh

# 启用 Console 登录
./03-create-users.sh --enable-console-login

# 或通过环境变量
ENABLE_CONSOLE_LOGIN=true ./03-create-users.sh
```

| 模式         | Console 登录 | API 访问 | 凭证文件 |
| ------------ | ------------ | -------- | -------- |
| 默认（禁用） | ❌           | ✅       | 不生成   |
| 启用         | ✅           | ✅       | 生成     |

**用户访问 SageMaker Studio 的方式：**

1. **Console 登录禁用**: 通过 `CreatePresignedDomainUrl` API 获取预签名 URL
2. **Console 登录启用**: 直接登录 AWS Console 访问 SageMaker Studio

## Execution Role 设计

### Trust Policy（信任策略）

所有 Execution Role 使用统一的 Trust Policy：

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

> 位置: `policies/trust-policy-sagemaker.json`

### 权限层次

**Domain Default Execution Role:**

| 顺序 | 权限                      | 说明                           |
| ---- | ------------------------- | ------------------------------ |
| 1    | AmazonSageMakerFullAccess | AWS 托管策略，SageMaker 全功能 |
| 2    | Canvas 策略组 (可选)      | 低代码 ML 平台，默认开启       |
| 3    | StudioAppPermissions      | 用户隔离，始终启用             |
| 4    | MLflowAppAccess (可选)    | 实验追踪，默认开启             |

**Project Execution Role (用于 User Profile):**

| 顺序 | 权限                      | 说明                       |
| ---- | ------------------------- | -------------------------- |
| 1    | AmazonSageMakerFullAccess | AWS 托管策略（必须先附加） |
| 2    | Canvas 策略组 (可选)      | 低代码 ML 平台，默认开启   |
| 3    | StudioAppPermissions      | 用户隔离，始终启用         |
| 4    | MLflowAppAccess (可选)    | 实验追踪，默认开启         |
| 5    | 项目自定义策略            | S3、ECR、CloudWatch 等权限 |

### Canvas 策略组（默认开启）

Canvas 是 SageMaker 的低代码 ML 平台。`ENABLE_CANVAS=true`（默认）时附加以下策略：

| 策略                                    | 用途                                       |
| --------------------------------------- | ------------------------------------------ |
| AmazonSageMakerCanvasFullAccess         | Canvas 核心功能                            |
| AmazonSageMakerCanvasAIServicesAccess   | AI 服务 (Bedrock, Textract, Comprehend 等) |
| AmazonSageMakerCanvasDataPrepFullAccess | 数据准备 (Data Wrangler, Glue, Athena)     |
| AmazonSageMakerCanvasDirectDeployAccess | 模型部署到 Endpoint (service-role 路径)    |

```bash
# 禁用 Canvas（减少权限范围）
ENABLE_CANVAS=false ./04-create-roles.sh
```

### Studio App Permissions（始终启用）

提供精细化的 Studio 权限隔离，**安全必须**：

| 功能               | 说明                              |
| ------------------ | --------------------------------- |
| Private Space 隔离 | 用户只能操作自己的私有空间        |
| Shared Space 协作  | 可以在共享空间创建/删除 App       |
| 预签名 URL         | 只能为自己的 Profile 生成登录 URL |
| 防误操作           | 防止用户误删他人资源              |

### MLflow App Access（默认开启）

提供 MLflow 实验追踪能力：

| 功能                | 说明                                 |
| ------------------- | ------------------------------------ |
| MLflow App 管理     | 创建/删除/描述 MLflow 应用           |
| 实验追踪            | 记录参数、指标、模型版本             |
| Model Registry 集成 | 与 SageMaker Model Registry 无缝对接 |
| Artifact 存储       | S3 存储实验 artifacts                |

```bash
# 禁用 MLflow（减少权限范围）
ENABLE_MLFLOW=false ./04-create-roles.sh
```

### 权限内容

**AmazonSageMakerFullAccess 包含:**

- SageMaker 全功能（Notebook, Processing, Training, Inference）
- 模型注册表、实验、Pipeline
- 数据科学助手、Amazon Q

**Canvas 策略组包含:**

- SageMaker Canvas 低代码 ML 平台
- AI 服务集成（Bedrock, Textract, Comprehend, Rekognition）
- 数据准备（Data Wrangler, Glue, Athena）
- 直接部署模型到 Endpoint

**项目自定义策略包含:**

- S3 项目桶读写
- S3 SageMaker 默认桶
- S3 共享资产桶（只读）
- CloudWatch Logs
- ECR 镜像仓库
- Amazon Q / Data Science Assistant

## 资源筛选

所有 IAM 资源使用统一路径 `/${COMPANY}-sagemaker/`，便于筛选：

```bash
# 假设 COMPANY=acme，筛选所有相关资源：

# Policies
aws iam list-policies --scope Local --path-prefix /acme-sagemaker/

# Groups
aws iam list-groups --path-prefix /acme-sagemaker/

# Users
aws iam list-users --path-prefix /acme-sagemaker/

# Roles
aws iam list-roles --path-prefix /acme-sagemaker/
```

**AWS Console 筛选**：在 IAM 控制台搜索框输入公司前缀（如 `acme`）。

## 脚本说明

### 01-create-policies.sh

创建以下策略（使用 `policies/` 目录下的模板）：

**通用策略:**

- `SageMaker-Studio-Base-Access` - 基础访问策略
- `SageMaker-ReadOnly-Access` - 只读策略（S3 限制为 `${COMPANY}-sm-*` 桶）
- `SageMaker-User-SelfService` - 用户自服务策略（修改密码、MFA、**强制 MFA**）
- `SageMaker-User-Boundary` - 权限边界策略
- `SageMaker-StudioAppPermissions` - Studio 用户隔离（安全必须）
- `SageMaker-MLflowAppAccess` - MLflow 实验追踪

**团队/项目策略:**

- `SageMaker-{Team}-Team-Access` - 团队访问策略
- `SageMaker-{Team}-{Project}-Access` - 项目访问策略
- `SageMaker-{Team}-{Project}-ExecutionPolicy` - 执行角色策略（项目 S3 隔离）

**安全策略说明：**

| 功能            | 状态                                         |
| --------------- | -------------------------------------------- |
| 修改密码        | ✅ 允许                                      |
| 设置 MFA        | ✅ 允许                                      |
| **强制 MFA**    | ✅ 未启用 MFA 时只能设置 MFA，其他操作被拒绝 |
| 创建 Access Key | ❌ 禁止（显式 Deny）                         |
| 查看所有 S3 桶  | ❌ 禁止（只能访问 `${COMPANY}-sm-*` 桶）     |
| 查看其他用户    | ❌ 禁止                                      |

### 02-create-groups.sh

创建以下组：

- `sagemaker-admins` - 管理员组
- `sagemaker-readonly` - 只读组
- `sagemaker-{team-fullname}` - 团队组
- `sagemaker-{team}-{project}` - 项目组

### 03-create-users.sh

创建用户并：

- 设置初始密码 (需要首次登录重置) - **仅当启用 Console 登录时**
- 应用 Permissions Boundary
- 添加 Tags (Team, Owner, ManagedBy)

**参数:**

```bash
./03-create-users.sh [--enable-console-login]
```

### 04-create-roles.sh

创建 SageMaker Execution Roles：

- Domain 默认执行角色（AmazonSageMakerFullAccess）
- 每个项目一个执行角色
- 信任 sagemaker.amazonaws.com (仅 `sts:AssumeRole`)
- 先附加 AmazonSageMakerFullAccess，再附加项目策略

### 05-bind-policies.sh

绑定策略到组：

- 管理员组 → AmazonSageMakerFullAccess
- 只读组 → ReadOnly-Access
- 团队组 → Base-Access + Team-Access
- 项目组 → Project-Access

### 06-add-users-to-groups.sh

添加用户到组：

- 每个用户加入团队组 + 项目组
- 管理员加入管理员组

## 执行顺序

必须按以下顺序执行（`setup-all.sh` 会自动处理）：

```
1. create-policies  # 先创建策略
2. create-groups    # 创建组
3. create-users     # 创建用户
4. create-roles     # 创建执行角色
5. bind-policies    # 绑定策略到组
6. add-users-to-groups  # 添加用户到组
```

## 策略模板

策略内容与 Shell 脚本分离，位于 `policies/` 目录：

| 模板文件                          | 说明                    | 变量                           |
| --------------------------------- | ----------------------- | ------------------------------ |
| `trust-policy-sagemaker.json`     | Trust Policy            | 无（静态）                     |
| `base-access.json.tpl`            | 基础访问                | `AWS_REGION`, `AWS_ACCOUNT_ID` |
| `team-access.json.tpl`            | 团队访问                | + `COMPANY`, `TEAM`            |
| `project-access.json.tpl`         | 项目访问                | + `PROJECT`                    |
| `execution-role.json.tpl`         | Execution Role 项目权限 | + `PROJECT`                    |
| `user-boundary.json.tpl`          | 权限边界                | `AWS_ACCOUNT_ID`, `COMPANY`    |
| `readonly.json.tpl`               | 只读访问                | 无                             |
| `self-service.json.tpl`           | 自助服务                | `AWS_ACCOUNT_ID`, `IAM_PATH`   |
| `studio-app-permissions.json.tpl` | Studio 用户隔离         | `AWS_REGION`, `AWS_ACCOUNT_ID` |
| `mlflow-app-access.json.tpl`      | MLflow 实验追踪         | `AWS_REGION`, `AWS_ACCOUNT_ID` |

详见 `policies/README.md`。

## 验证

运行验证脚本检查所有资源：

```bash
./verify.sh
```

输出示例：

```
Resource Summary:
  +-----------------+----------+----------+
  | Resource        | Expected | Actual   |
  +-----------------+----------+----------+
  | Policies        |       11 |       11 |
  | Groups          |        7 |        7 |
  | Users           |        6 |        6 |
  | Roles           |        3 |        3 |
  +-----------------+----------+----------+

--- IAM Policies ---
  ✓ SageMaker-Studio-Base-Access
  ✓ SageMaker-ReadOnly-Access
  ...

--- IAM Groups ---
  ✓ sagemaker-admins
  ✓ sagemaker-risk-control
  ...

Verification PASSED - All resources configured correctly
```

## 清理资源

⚠️ **危险操作** - 删除所有创建的 IAM 资源：

```bash
# 交互式确认
./cleanup.sh

# 强制删除 (跳过确认)
./cleanup.sh --force
```

## 安全注意事项

1. **凭证文件**: `output/user-credentials.txt` 包含初始密码（仅启用 Console 登录时生成），请：

   - 安全传递给用户
   - 传递后立即删除文件
   - 不要提交到 Git

2. **Permissions Boundary**: 所有用户都应用了权限边界，防止权限提升

3. **IAM Path**: 所有资源使用 `/${COMPANY}-sagemaker/` 路径，便于管理和审计

4. **最小权限**: 用户只能访问自己项目的资源

5. **Console 登录**: 默认禁用，推荐通过预签名 URL 访问 SageMaker Studio

## 常见问题

### Q: 策略版本达到上限怎么办？

A: 脚本会自动删除最旧的非默认版本。如需手动处理：

```bash
aws iam list-policy-versions --policy-arn <ARN>
aws iam delete-policy-version --policy-arn <ARN> --version-id v1
```

### Q: 如何添加新用户？

A: 编辑 `.env` 文件添加用户，然后运行创建和加组脚本（脚本会自动跳过已存在的用户）：

```bash
# 1. 编辑 .env，在对应项目的用户列表中添加新用户
#    例如：给 rc 团队的 fraud-detection 项目添加 frank
vi .env
#    修改: RC_FRAUD_DETECTION_USERS="alice bob"
#    改为: RC_FRAUD_DETECTION_USERS="alice bob frank"

# 2. 运行创建用户脚本（会跳过已存在的 alice、bob）
./03-create-users.sh [--enable-console-login]

# 3. 运行加组脚本（将新用户添加到团队组和项目组）
./06-add-users-to-groups.sh

# 4. 验证
./verify.sh
```

新用户将获得：

- 用户名：`sm-rc-frank`
- 初始密码：保存在 `output/user-credentials.txt`（仅启用 Console 登录时）
- 所属组：`sagemaker-risk-control` + `sagemaker-rc-fraud-detection`

### Q: 如何添加新项目？

A: 编辑 `.env` 文件添加项目配置，然后重新运行 `setup-all.sh`（会跳过已存在的资源）：

```bash
# 1. 编辑 .env，添加新项目
vi .env
#    在团队项目列表中添加: RC_PROJECTS="fraud-detection anti-money-laundering new-project"
#    添加项目用户变量: RC_NEW_PROJECT_USERS="grace henry"

# 2. 运行 setup-all.sh（会跳过已存在的资源，只创建新项目相关资源）
./setup-all.sh

# 3. 验证
./verify.sh
```

新项目将创建：

- Policy: `SageMaker-RiskControl-NewProject-Access` + `ExecutionPolicy`
- Group: `sagemaker-rc-new-project`
- Role: `SageMaker-RiskControl-NewProject-ExecutionRole`
- Users: `sm-rc-grace`, `sm-rc-henry`

### Q: 如何查看创建了哪些资源？

A: 使用路径前缀筛选：

```bash
# 查看所有资源
./verify.sh

# 或手动查询
aws iam list-users --path-prefix /${COMPANY}-sagemaker/
aws iam list-groups --path-prefix /${COMPANY}-sagemaker/
aws iam list-roles --path-prefix /${COMPANY}-sagemaker/
aws iam list-policies --scope Local --path-prefix /${COMPANY}-sagemaker/
```

### Q: 如何修改策略模板？

A: 直接编辑 `policies/` 目录下的模板文件，然后运行：

```bash
./01-create-policies.sh --force
```

### Q: 为什么 User Profile 的 Execution Role 需要 AmazonSageMakerFullAccess？

A: SageMaker 的很多功能（Processing Job, Training Job, Inference）需要 AmazonSageMakerFullAccess 中的权限。项目自定义策略只补充 S3、ECR 等资源的权限。

### Q: 如何禁用 Canvas 功能？

A: 在 `.env.shared` 或 `.env.local` 中设置：

```bash
ENABLE_CANVAS=false
```

或者运行时指定：

```bash
ENABLE_CANVAS=false ./04-create-roles.sh
```

禁用后，Execution Role 不会附加 Canvas 相关的 4 个策略，减少权限范围。

## 相关文档

- [02-iam-design.md](../../docs/02-iam-design.md) - IAM 设计文档
- [05-sagemaker-domain.md](../../docs/05-sagemaker-domain.md) - Domain 创建
- [06-user-profile.md](../../docs/06-user-profile.md) - User Profile 创建
- [policies/README.md](./policies/README.md) - 策略模板说明
