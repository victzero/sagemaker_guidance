# 04 - SageMaker Domain 脚本

创建和配置 SageMaker Domain (VPCOnly 模式 + IAM 认证)。

## 前置条件

1. 已完成 `01-iam/` IAM 资源创建
2. 已完成 `02-vpc/` VPC Endpoints 和安全组创建
3. 已完成 `03-s3/` S3 Buckets 创建
4. 已配置 `.env.shared` 中的 VPC 信息

## 快速开始

```bash
# 1. 配置环境变量（可选，使用默认值也可）
cp .env.local.example .env.local
vi .env.local

# 2. 一键执行
./setup-all.sh

# 3. 验证
./verify.sh
```

## 创建的资源

| 资源 | 名称 | 说明 |
|------|------|------|
| SageMaker Domain | `{company}-ml-platform` | VPCOnly + IAM 认证 |
| Lifecycle Config | `auto-shutdown-60min` | 空闲 60 分钟自动关机 |

## 脚本说明

| 脚本 | 功能 |
|------|------|
| `setup-all.sh` | 主控脚本，按顺序执行所有配置 |
| `check.sh` | **前置检查和诊断** |
| `01-create-domain.sh` | 创建 SageMaker Domain |
| `02-create-lifecycle-config.sh` | 创建自动关机脚本 |
| `03-attach-lifecycle.sh` | 绑定 Lifecycle Config 到 Domain |
| `verify.sh` | 验证配置 |
| `cleanup.sh` | 清理所有资源（危险！） |

## 问题诊断

### 创建前检查

```bash
# 完整检查（推荐）
./check.sh

# 快速检查
./check.sh --quick
```

### 创建失败后诊断

```bash
# 诊断失败的 Domain
./check.sh --diagnose
```

### 检查项目

| 检查项 | 说明 |
|--------|------|
| AWS 凭证 | CLI 配置和账号匹配 |
| VPC DNS | DNS Hostnames/Support 必须启用 |
| 子网 | 存在性、可用 IP、高可用性 |
| 安全组 | Studio 安全组和入站规则 |
| VPC Endpoints | 5 个必需 Endpoint 状态 |
| IAM Roles | Execution Roles 存在性 |
| Domain 状态 | 如存在，检查失败原因 |

## 配置参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `DOMAIN_NAME` | `{company}-ml-platform` | Domain 名称 |
| `IDLE_TIMEOUT_MINUTES` | `60` | 空闲超时（分钟） |
| `DEFAULT_INSTANCE_TYPE` | `ml.t3.medium` | 默认实例类型 |
| `DEFAULT_EBS_SIZE_GB` | `100` | 默认 EBS 大小 |

## 输出文件

执行后生成以下文件：

```
output/
├── domain-info.env        # Domain ID, EFS ID 等
└── lifecycle-config.env   # Lifecycle Config ARN
```

## 验证命令

```bash
# 列出 Domains
aws sagemaker list-domains

# 查看 Domain 详情
aws sagemaker describe-domain --domain-id d-xxxxxxxxx

# 列出 Lifecycle Configs
aws sagemaker list-studio-lifecycle-configs
```

## 清理

⚠️ **警告**: 清理将删除所有 User Profiles、Spaces、EFS 数据！

```bash
# 需要手动输入 DELETE 确认
./cleanup.sh

# 跳过确认（危险！）
./cleanup.sh --force
```

## 下一步

1. 创建 User Profiles: `cd ../05-user-profiles && ./setup-all.sh`
2. 创建 Shared Spaces: `cd ../06-spaces && ./setup-all.sh`

## 参考文档

- [05-SageMaker Domain 设计](../../docs/05-sagemaker-domain.md)
- [08-实施步骤指南](../../docs/08-implementation-guide.md)

