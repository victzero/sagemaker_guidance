# SageMaker S3 Data Management Scripts

基于 [04-s3-data-management.md](../../docs/04-s3-data-management.md) 设计文档的 AWS CLI 自动化脚本。

## 快速开始

```bash
# 1. 复制并编辑环境变量
cp .env.example .env
vi .env  # 填入公司名称、团队、项目等信息

# 2. 执行创建 (显示预览后确认)
./setup-all.sh

# 3. 验证配置
./verify.sh
```

## 目录结构

```
scripts/s3/
├── .env.example              # 环境变量模板
├── .env                      # 实际环境变量 (不提交到 Git)
├── 00-init.sh               # 初始化和工具函数
├── 01-create-buckets.sh     # 创建 S3 Buckets
├── 02-configure-policies.sh # 配置 Bucket Policies
├── 03-configure-lifecycle.sh # 配置生命周期规则
├── setup-all.sh             # 主控脚本
├── verify.sh                # 验证配置
├── cleanup.sh               # 清理资源 (危险!)
├── output/                  # 生成的配置文件
│   ├── buckets.env
│   ├── policy-*.json
│   └── lifecycle-*.json
└── README.md
```

## 创建的 Buckets

| Bucket 名称 | 用途 |
|------------|------|
| `{company}-sm-rc-project-a` | 风控项目 A |
| `{company}-sm-rc-project-b` | 风控项目 B |
| `{company}-sm-algo-project-x` | 算法项目 X |
| `{company}-sm-algo-project-y` | 算法项目 Y |
| `{company}-sm-shared-assets` | 共享资源 |

## Bucket 目录结构

### 项目 Bucket
```
{bucket}/
├── raw/                 # 原始数据
│   ├── uploads/
│   └── external/
├── processed/           # 处理后数据
│   ├── cleaned/
│   └── transformed/
├── features/            # 特征数据
│   └── v1/
├── models/              # 模型文件
│   ├── training/
│   ├── artifacts/
│   └── registry/
├── notebooks/           # Notebook 备份
│   └── archived/
├── outputs/             # 输出结果
│   ├── reports/
│   └── predictions/
└── temp/                # 临时文件
```

### 共享 Bucket
```
{bucket}/
├── scripts/             # 共享脚本
│   ├── preprocessing/
│   └── utils/
├── containers/          # 容器配置
│   └── dockerfiles/
├── datasets/            # 共享数据集
│   └── reference/
└── documentation/       # 文档
```

## Bucket 配置

| 配置项 | 值 |
|--------|-----|
| 版本控制 | Enabled |
| 加密 | SSE-S3 (或 SSE-KMS) |
| 公开访问 | 全部阻止 |
| 标签 | Team, Project, Environment, CostCenter |

## 生命周期规则

| 路径 | 规则 | 天数 |
|------|------|------|
| temp/* | 删除 | 7 |
| models/training/* | 转 IA | 30 |
| notebooks/archived/* | 转 IA → Glacier | 60 → 180 |
| outputs/predictions/* | 删除 | 90 |
| 非当前版本 | 删除 | 90 |
| 未完成上传 | 中止 | 7 |

## Bucket Policy

### 项目 Bucket
- 允许项目 Execution Role 完全访问
- 允许项目成员 (sm-{team}-*) Console 访问
- 可选: 限制仅 VPC 内访问

### 共享 Bucket
- 允许所有 Execution Role 只读
- 允许所有 SageMaker 用户只读
- 允许管理员 (sm-admin-*) 完全访问

## 环境变量说明

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `COMPANY` | 公司前缀 | - |
| `ENCRYPTION_TYPE` | 加密类型 | SSE-S3 |
| `KMS_KEY_ID` | KMS 密钥 ID | - |
| `ENABLE_VERSIONING` | 版本控制 | true |
| `ENABLE_LIFECYCLE_RULES` | 生命周期规则 | true |
| `RESTRICT_TO_VPC` | VPC 限制 | false |
| `VPC_ID` | VPC ID | - |

## 验证

```bash
./verify.sh
```

输出示例:
```
--- Project Buckets ---
  ✓ acme-sm-rc-project-a exists
    ✓ Versioning: Enabled
    ✓ Encryption: AES256
    ✓ Public Access: Blocked
    ✓ Bucket Policy: Configured
    ✓ Lifecycle Rules: Configured

Verification PASSED
```

## 清理资源

⚠️ **危险操作** - 删除所有 Bucket 及其内容：

```bash
./cleanup.sh
```

## SSE-KMS 加密 (可选)

如需使用 KMS 加密：

1. 创建 KMS 密钥：
```bash
aws kms create-key --description "SageMaker S3 Encryption"
```

2. 配置环境变量：
```bash
ENCRYPTION_TYPE=SSE-KMS
KMS_KEY_ID=12345678-1234-1234-1234-123456789abc
```

3. 确保 Execution Roles 有 KMS 权限

## 故障排除

### Bucket 创建失败

- 检查 Bucket 名称是否全球唯一
- 检查是否有足够的 IAM 权限

### Policy 应用失败

- 检查 Execution Role 是否存在
- 检查 Policy JSON 语法

### 生命周期规则不生效

- 规则需要时间生效 (可能 24 小时)
- 检查前缀是否正确

## 相关文档

- [04-s3-data-management.md](../../docs/04-s3-data-management.md) - S3 设计
- [02-iam-design.md](../../docs/02-iam-design.md) - IAM 权限设计
- [scripts/iam/](../iam/) - IAM 脚本
