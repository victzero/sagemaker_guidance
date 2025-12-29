# SageMaker IAM Setup Scripts

基于 [02-iam-design.md](../../docs/02-iam-design.md) 设计文档的 AWS CLI 自动化脚本。

## 快速开始

```bash
# 1. 复制并编辑环境变量
cp .env.example .env
vi .env  # 填入实际值

# 2. 预览将要执行的命令 (dry-run 模式)
./setup-all.sh --dry-run

# 3. 执行创建
./setup-all.sh

# 4. 验证配置
./verify.sh
```

## 目录结构

```
scripts/iam/
├── .env.example          # 环境变量模板
├── .env                  # 实际环境变量 (不提交到 Git)
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

## 环境变量说明

| 变量 | 说明 | 示例 |
|------|------|------|
| `COMPANY` | 公司/组织前缀 | `acme` |
| `AWS_ACCOUNT_ID` | AWS 账号 ID | `123456789012` |
| `AWS_REGION` | AWS 区域 | `ap-southeast-1` |
| `TEAMS` | 团队列表 | `"rc algo"` |
| `TEAM_RC_FULLNAME` | 团队全称 | `risk-control` |
| `RC_PROJECTS` | 团队项目 | `"project-a project-b"` |
| `RC_PROJECT_A_USERS` | 项目用户 | `"alice bob carol"` |
| `DRY_RUN` | 仅打印命令 | `true/false` |

## 脚本说明

### 01-create-policies.sh

创建以下策略：
- `SageMaker-Studio-Base-Access` - 基础访问策略
- `SageMaker-ReadOnly-Access` - 只读策略
- `SageMaker-User-Boundary` - 权限边界策略
- `SageMaker-{Team}-Team-Access` - 团队访问策略
- `SageMaker-{Team}-{Project}-Access` - 项目访问策略
- `SageMaker-{Team}-{Project}-ExecutionPolicy` - 执行角色策略

### 02-create-groups.sh

创建以下组：
- `sagemaker-admins` - 管理员组
- `sagemaker-readonly` - 只读组
- `sagemaker-{team-fullname}` - 团队组
- `sagemaker-{team}-{project}` - 项目组

### 03-create-users.sh

创建用户并：
- 设置初始密码 (需要首次登录重置)
- 应用 Permissions Boundary
- 添加 Tags (Team, Owner, ManagedBy)

### 04-create-roles.sh

创建 SageMaker Execution Roles：
- 每个项目一个执行角色
- 信任 sagemaker.amazonaws.com
- 绑定对应的 ExecutionPolicy

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

## 验证

运行验证脚本检查所有资源：

```bash
./verify.sh
```

输出示例：
```
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
# 预览将要删除的内容
./cleanup.sh

# 强制删除 (跳过确认)
./cleanup.sh --force
```

## 安全注意事项

1. **凭证文件**: `output/user-credentials.txt` 包含初始密码，请：
   - 安全传递给用户
   - 传递后立即删除文件
   - 不要提交到 Git

2. **Permissions Boundary**: 所有用户都应用了权限边界，防止权限提升

3. **IAM Path**: 所有资源使用 `/sagemaker/` 路径，便于管理和审计

4. **最小权限**: 用户只能访问自己项目的资源

## 常见问题

### Q: 策略版本达到上限怎么办？

A: 脚本会自动删除最旧的非默认版本。如需手动处理：

```bash
aws iam list-policy-versions --policy-arn <ARN>
aws iam delete-policy-version --policy-arn <ARN> --version-id v1
```

### Q: 如何添加新用户？

A: 编辑 `.env` 文件添加用户，然后运行：

```bash
./03-create-users.sh
./06-add-users-to-groups.sh
```

### Q: 如何添加新项目？

A: 编辑 `.env` 文件添加项目，然后按顺序运行所有脚本或：

```bash
./setup-all.sh  # 会跳过已存在的资源
```

## 相关文档

- [02-iam-design.md](../../docs/02-iam-design.md) - IAM 设计文档
- [05-sagemaker-domain.md](../../docs/05-sagemaker-domain.md) - Domain 创建
- [06-user-profile.md](../../docs/06-user-profile.md) - User Profile 创建
