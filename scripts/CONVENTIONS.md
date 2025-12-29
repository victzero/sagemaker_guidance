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

### 1.3 颜色输出

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

每个脚本目录应包含：

```
scripts/{NN}-{name}/
├── .env.example          # 环境变量模板（详细注释）
├── .env                  # 实际配置（不提交 Git）
├── 00-init.sh           # 初始化和公共函数
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

---

## 5. 脚本功能规范

### 5.1 setup-all.sh

- 显示详细的资源预览（列出所有将创建的资源名称）
- 显示资源统计（Policies、Groups、Users、Roles 数量）
- 确认后执行
- 执行完成后显示筛选命令

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

## 6. .env.example 规范

必须包含：

1. **头部说明**: 使用方法
2. **分节注释**: 清晰分隔各配置块
3. **变量说明**: 每个变量上方有注释
4. **示例值**: 提供合理的示例
5. **尾部说明**: 列出将创建的资源类型

---

## 7. 幂等性要求

所有脚本必须支持幂等操作：

- **创建前检查**: 资源存在则跳过
- **重复运行安全**: 多次运行结果相同
- **增量更新支持**: 添加新资源时只创建新增部分

```bash
# 示例：创建用户前检查
if aws iam get-user --user-name "$username" &> /dev/null; then
    log_warn "User $username already exists, skipping..."
    return 0
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
