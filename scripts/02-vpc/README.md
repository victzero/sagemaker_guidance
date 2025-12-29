# SageMaker VPC Network Setup Scripts

基于 [03-vpc-network.md](../../docs/03-vpc-network.md) 设计文档的 AWS CLI 自动化脚本。

## 前提条件

- 已有 VPC 和 Private Subnets
- VPC 启用了 DNS Hostnames 和 DNS Support
- 有足够的 IP 地址空间 (建议每子网 128+ IPs)

## 快速开始

```bash
# 1. 复制并编辑环境变量
cp .env.example .env
vi .env  # 填入 VPC ID、Subnet IDs 等

# 2. 预览命令 (dry-run 模式)
./setup-all.sh --dry-run

# 3. 执行创建
./setup-all.sh

# 4. 验证配置
./verify.sh
```

## 目录结构

```
scripts/vpc/
├── .env.example              # 环境变量模板
├── .env                      # 实际环境变量 (不提交到 Git)
├── 00-init.sh               # 初始化和工具函数
├── 01-create-security-groups.sh  # 创建安全组
├── 02-create-vpc-endpoints.sh    # 创建 VPC Endpoints
├── setup-all.sh             # 主控脚本
├── verify.sh                # 验证配置
├── cleanup.sh               # 清理资源
├── output/                  # 生成的配置文件
│   ├── security-groups.env
│   └── vpc-endpoints.env
└── README.md
```

## 创建的资源

### 安全组

| 安全组名称 | 用途 |
|-----------|------|
| `sg-sagemaker-studio` | SageMaker Studio 实例 |
| `sg-sagemaker-vpc-endpoints` | VPC Endpoints |

### VPC Endpoints (必需)

| Endpoint | 类型 | 用途 |
|----------|------|------|
| sagemaker.api | Interface | SageMaker API |
| sagemaker.runtime | Interface | SageMaker Runtime |
| notebook | Interface | SageMaker Notebook |
| sagemaker.studio | Interface | SageMaker Studio |
| sts | Interface | AWS STS |
| logs | Interface | CloudWatch Logs |
| s3 | Gateway | S3 访问 |

### VPC Endpoints (可选)

| Endpoint | 环境变量 | 用途 |
|----------|----------|------|
| ecr.api | CREATE_ECR_ENDPOINTS=true | ECR API |
| ecr.dkr | CREATE_ECR_ENDPOINTS=true | ECR Docker |
| kms | CREATE_KMS_ENDPOINT=true | KMS 加密 |
| ssm | CREATE_SSM_ENDPOINT=true | Systems Manager |

## 环境变量说明

| 变量 | 说明 | 必需 |
|------|------|------|
| `VPC_ID` | 现有 VPC ID | ✅ |
| `VPC_CIDR` | VPC CIDR 范围 | ✅ |
| `PRIVATE_SUBNET_1_ID` | Private Subnet 1 | ✅ |
| `PRIVATE_SUBNET_2_ID` | Private Subnet 2 | ✅ |
| `ROUTE_TABLE_1_ID` | 路由表 1 (S3 Gateway) | ✅ |
| `ROUTE_TABLE_2_ID` | 路由表 2 | 可选 |
| `CREATE_ECR_ENDPOINTS` | 是否创建 ECR Endpoints | 可选 |

## 安全组规则

### sg-sagemaker-studio

**入站规则:**
- All Traffic from self (Studio 内部通信)
- HTTPS (443) from VPC CIDR

**出站规则:**
- All Traffic to self
- HTTPS (443) to 0.0.0.0/0 (默认)

### sg-sagemaker-vpc-endpoints

**入站规则:**
- HTTPS (443) from VPC CIDR

## 验证

```bash
./verify.sh
```

输出示例:
```
--- VPC DNS Settings ---
  ✓ DNS Hostnames: Enabled
  ✓ DNS Support: Enabled

--- Security Groups ---
  ✓ sg-sagemaker-studio: sg-0abc123
  ✓ sg-sagemaker-vpc-endpoints: sg-0def456

--- VPC Endpoints ---
Required Endpoints:
  ✓ sagemaker.api: vpce-0abc123 (available)
  ✓ s3: vpce-0def456 (available)
  ...

Verification PASSED
```

## 清理资源

⚠️ **危险操作**：

```bash
./cleanup.sh
```

## 故障排除

### Endpoint 创建失败

1. 检查子网是否在正确的可用区
2. 检查安全组是否允许 HTTPS 入站
3. 检查 VPC 是否启用了 DNS 设置

### Studio 无法连接

1. 检查所有必需的 Endpoints 是否处于 `available` 状态
2. 检查安全组规则是否正确
3. 验证子网有足够的 IP 地址

## 相关文档

- [03-vpc-network.md](../../docs/03-vpc-network.md) - VPC 网络设计
- [05-sagemaker-domain.md](../../docs/05-sagemaker-domain.md) - Domain 创建
