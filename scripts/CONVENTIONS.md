# SageMaker 脚本开发规范

所有脚本（01-iam, 02-vpc, 03-s3 等）统一遵循以下规范。

---

## 1. Shell 脚本规范

### 1.1 兼容性

- **目标环境**: AWS CloudShell (Amazon Linux 2, Bash 4.x+)
- **可使用的 Bash 4.x 特性**:
  - `${var^^}` - 转大写
  - `${var,,}` - 转小写
  - `${var^}` - 首字母大写
  - `${var//pattern/replacement}` - 字符串替换

### 1.2 `set -e` 安全

在 `set -e` 模式下，以下操作需要特别处理：

```bash
# ❌ 错误：当 count=0 时会导致脚本退出
((count++))

# ✅ 正确：始终返回成功
((count++)) || true
```

### 1.3 AWS CLI 配置

禁用 AWS CLI 分页器，避免长输出阻塞脚本执行：

```bash
# 在 check_aws_cli() 中设置
export AWS_PAGER=""
```

### 1.4 颜色输出

统一使用以下颜色函数：

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
```

---

## 2. 环境变量命名规范

### 2.1 核心变量（所有脚本共享）

| 变量             | 说明         | 示例             |
| ---------------- | ------------ | ---------------- |
| `COMPANY`        | 公司前缀     | `acme`           |
| `AWS_ACCOUNT_ID` | AWS 账号 ID  | `123456789012`   |
| `AWS_REGION`     | AWS 区域     | `ap-southeast-1` |
| `TEAMS`          | 团队 ID 列表 | `"rc algo"`      |

### 2.2 团队配置变量

```bash
# 格式: TEAM_{TEAM_ID}_FULLNAME
# TEAM_ID 必须大写

TEAM_RC_FULLNAME=risk-control
TEAM_ALGO_FULLNAME=algorithm
```

### 2.3 项目配置变量

```bash
# 格式: {TEAM_ID}_PROJECTS
# TEAM_ID 必须大写

RC_PROJECTS="fraud-detection anti-money-laundering"
ALGO_PROJECTS="recommendation-engine"
```

### 2.4 用户配置变量

```bash
# 格式: {TEAM_ID}_{PROJECT_NAME}_USERS
#
# 转换规则:
#   - TEAM_ID: 小写 → 大写
#   - PROJECT_NAME: 小写 → 大写, 连字符(-) → 下划线(_)
#
# 示例:
#   team=rc, project=fraud-detection
#   → RC_FRAUD_DETECTION_USERS

RC_FRAUD_DETECTION_USERS="alice bob"
RC_ANTI_MONEY_LAUNDERING_USERS="carol"
ALGO_RECOMMENDATION_ENGINE_USERS="david eve"
```

---

## 3. IAM 资源命名规范

### 3.1 IAM Path

所有 IAM 资源使用统一路径：

```
/${COMPANY}-sagemaker/
```

示例：`/acme-sagemaker/`

### 3.2 Policies 命名

| 类型     | 格式                                                 | 示例                                                   |
| -------- | ---------------------------------------------------- | ------------------------------------------------------ |
| 基础策略 | `SageMaker-{功能}-Access`                            | `SageMaker-Studio-Base-Access`                         |
| 权限边界 | `SageMaker-User-Boundary`                            | `SageMaker-User-Boundary`                              |
| 团队策略 | `SageMaker-{TeamFullname}-Team-Access`               | `SageMaker-RiskControl-Team-Access`                    |
| 项目策略 | `SageMaker-{TeamFullname}-{Project}-Access`          | `SageMaker-RiskControl-FraudDetection-Access`          |
| 执行策略 | `SageMaker-{TeamFullname}-{Project}-ExecutionPolicy` | `SageMaker-RiskControl-FraudDetection-ExecutionPolicy` |

**名称格式化规则** (`format_name` 函数)：

- 输入: `risk-control` 或 `fraud-detection`
- 输出: `RiskControl` 或 `FraudDetection`
- 规则: 按连字符分割，每部分首字母大写，然后拼接

### 3.3 Groups 命名

| 类型   | 格式                         | 示例                           |
| ------ | ---------------------------- | ------------------------------ |
| 平台组 | `sagemaker-{role}`           | `sagemaker-admins`             |
| 团队组 | `sagemaker-{team-fullname}`  | `sagemaker-risk-control`       |
| 项目组 | `sagemaker-{team}-{project}` | `sagemaker-rc-fraud-detection` |

**注意**: Groups 使用 kebab-case（保留连字符）

### 3.4 Users 命名

| 类型     | 格式               | 示例             |
| -------- | ------------------ | ---------------- |
| 管理员   | `sm-admin-{name}`  | `sm-admin-jason` |
| 团队用户 | `sm-{team}-{name}` | `sm-rc-alice`    |

### 3.5 Roles 命名

| 类型     | 格式                                               | 示例                                                 |
| -------- | -------------------------------------------------- | ---------------------------------------------------- |
| 执行角色 | `SageMaker-{TeamFullname}-{Project}-ExecutionRole` | `SageMaker-RiskControl-FraudDetection-ExecutionRole` |

---

## 4. 脚本目录结构

### 4.1 根目录（共享配置）

```
scripts/
├── .env.shared.example   # 共享环境变量模板
├── .env.shared           # 共享配置（不提交 Git）
├── common.sh             # 共享函数库
├── CONVENTIONS.md        # 开发规范
└── README.md             # 总体说明
```

### 4.2 模块目录

每个脚本目录应包含：

```
scripts/{NN}-{name}/
├── .env.local.example    # 模块特有配置模板
├── .env.local            # 模块特有配置（不提交 Git，可选）
├── 00-init.sh           # 初始化（source common.sh）
├── 01-*.sh              # 子脚本 1
├── 02-*.sh              # 子脚本 2
├── ...
├── setup-all.sh         # 主控脚本
├── verify.sh            # 验证脚本
├── cleanup.sh           # 清理脚本
├── output/              # 生成的文件
├── README.md            # 使用说明
└── RESOURCES.md         # 资源说明（可选）
```

### 4.3 环境变量加载顺序

```bash
# common.sh 中的 load_env() 函数加载顺序：
1. scripts/.env.shared      # 共享配置（必须）
2. scripts/{module}/.env.local  # 模块特有配置（可选，会覆盖共享配置）
3. scripts/{module}/.env    # 兼容旧配置（警告，建议迁移）
```

---

## 5. 脚本功能规范

### 5.1 setup-all.sh（资源预览模式）

**核心要求**：执行前必须打印完整的资源清单，让用户确认后再执行。

#### 5.1.1 标准结构

```bash
#!/bin/bash
set -e

# 1. 加载环境和验证
source "${SCRIPT_DIR}/../common.sh"
load_env
validate_base_env
validate_team_env  # 或模块特有验证
check_aws_cli

# 2. 设置模块特有配置
MODULE_VAR="${MODULE_VAR:-default_value}"

# 3. 打印资源清单（确认前）
echo -e "${YELLOW}This script will create the following AWS {MODULE} resources:${NC}"
# ... 详细资源列表 ...

# 4. 打印 Summary
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: X resources, Y policies, ...${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 5. 打印筛选命令
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws ... --filters ..."

# 6. 确认执行
read -p "Do you want to proceed? [y/N] " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi

# 7. 执行子脚本
run_step 1 "01-xxx.sh" "Description"
run_step 2 "02-xxx.sh" "Description"

# 8. 打印完成信息和后续步骤
```

#### 5.1.2 资源列表格式

使用 `【分类名】` 格式分组，每组包含：

```bash
echo -e "${BLUE}【Buckets】${NC}"
echo "  Team [rc - risk-control]:"
echo "    - acme-sm-rc-fraud-detection"
echo "    - acme-sm-rc-anti-money-laundering"
echo "  Total: $count buckets"
echo ""
```

#### 5.1.3 各模块资源分组

| 模块   | 资源分组                                                                                                                 |
| ------ | ------------------------------------------------------------------------------------------------------------------------ |
| 01-iam | 【Policies】【Groups】【Users】【Execution Roles】                                                                       |
| 02-vpc | 【Security Groups】【VPC Endpoints - Required】【VPC Endpoints - Optional】【Endpoint Configuration】                    |
| 03-s3  | 【Buckets】【Bucket Policies】【Lifecycle Rules】【Directory Structures】【Bucket Configurations】【Lifecycle Settings】 |

#### 5.1.4 Summary 格式

使用 `━━━` 分隔线包裹总计：

```bash
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Summary: $count1 resources, $count2 policies, ...${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
```

#### 5.1.5 筛选命令

执行前后都应显示 AWS CLI 筛选命令：

```bash
echo -e "${YELLOW}Filter resources later with:${NC}"
echo "  aws iam list-policies --scope Local --path-prefix /acme-sagemaker/"
echo "  aws s3 ls | grep acme-sm-"
echo "  aws ec2 describe-vpc-endpoints --filters \"Name=tag:ManagedBy,Values=...\""
```

#### 5.1.6 完成信息

执行后显示：

- Duration（耗时）
- 创建的资源列表
- 资源 ID 保存位置
- 验证命令
- 后续步骤

### 5.2 verify.sh

- 统计预期 vs 实际资源数量
- 逐项验证每个资源是否存在
- 验证关联关系（如用户组成员、策略绑定）
- 显示实际资源列表
- 输出筛选命令

### 5.3 cleanup.sh

- 显示警告信息
- 要求输入 `DELETE` 确认
- 支持 `--force` 跳过确认
- 按正确顺序删除（先解除关联，再删除资源）

---

## 6. 环境变量文件规范

### 6.1 共享配置 (.env.shared.example)

位于 `scripts/` 根目录，包含所有模块共享的变量：

- **AWS 基础配置**: COMPANY, AWS_ACCOUNT_ID, AWS_REGION
- **团队配置**: TEAMS, TEAM\_\*\_FULLNAME
- **项目配置**: \*\_PROJECTS
- **用户配置**: ADMIN_USERS, \*\_USERS
- **通用设置**: OUTPUT_DIR

### 6.2 模块特有配置 (.env.local.example)

位于各模块目录，只包含该模块特有的变量：

| 模块   | 特有变量                                         |
| ------ | ------------------------------------------------ |
| 01-iam | IAM_PATH                                         |
| 02-vpc | VPC*ID, VPC_CIDR, PRIVATE_SUBNET*\*\_ID          |
| 03-s3  | ENCRYPTION_TYPE, ENABLE_VERSIONING, Lifecycle 等 |

### 6.3 文件格式要求

必须包含：

1. **头部说明**: 使用方法和共享配置位置
2. **分节注释**: 清晰分隔各配置块
3. **变量说明**: 每个变量上方有注释
4. **示例值**: 提供合理的示例
5. **尾部说明**: 标明哪些配置已移至共享文件

---

## 7. 幂等性要求

所有脚本必须支持幂等操作：

- **创建前检查**: 资源存在则跳过创建
- **子资源检查**: 即使父资源存在，仍需检查子资源（如 LoginProfile）
- **重复运行安全**: 多次运行结果相同
- **增量更新支持**: 添加新资源时只创建新增部分

```bash
# 示例：创建用户（包含 LoginProfile 检查）
if aws iam get-user --user-name "$username" &> /dev/null; then
    log_warn "User $username already exists"
else
    aws iam create-user --user-name "$username" ...
fi

# 即使用户存在，仍需检查 LoginProfile
if ! aws iam get-login-profile --user-name "$username" &> /dev/null; then
    aws iam create-login-profile --user-name "$username" ...
fi
```

---

## 8. 错误处理

- 使用 `set -e` 遇错即停
- 关键操作添加错误检查
- 提供清晰的错误信息和修复建议

```bash
if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
    log_error "Account ID mismatch!"
    echo "  .env configured:  $AWS_ACCOUNT_ID"
    echo "  Current account:  $current_account"
    echo ""
    echo "Please update AWS_ACCOUNT_ID in .env file"
    exit 1
fi
```
