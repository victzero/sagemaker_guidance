# SageMaker VPC Network Setup Scripts

基于 [03-vpc-network.md](../../docs/03-vpc-network.md) 设计文档的 AWS CLI 自动化脚本。

## 前提条件

- 已有 VPC 和 Private Subnets
- VPC 启用了 DNS Hostnames 和 DNS Support
- 有足够的 IP 地址空间 (建议每子网 128+ IPs)

## 快速开始

```bash
# 1. 确保已配置共享环境变量
cat ../scripts/.env.shared  # 检查 COMPANY, AWS_REGION 等

# 2. 复制并编辑 VPC 特有配置
cp .env.local.example .env.local
vi .env.local  # 填入 VPC ID、Subnet IDs、Route Table 等

# 3. 执行创建 (显示预览后确认)
./setup-all.sh

# 4. 验证配置
./verify.sh
```

## 目录结构

```
scripts/02-vpc/
├── .env.local.example        # VPC 模块环境变量模板
├── .env.local                # VPC 模块实际配置 (不提交到 Git)
├── 00-init.sh                # 初始化和工具函数
├── 01-create-security-groups.sh  # 创建安全组
├── 02-create-vpc-endpoints.sh    # 创建 VPC Endpoints
├── setup-all.sh              # 主控脚本
├── verify.sh                 # 验证配置
├── cleanup.sh                # 清理资源
├── output/                   # 生成的配置文件
│   ├── security-groups.env
│   └── vpc-endpoints.env
└── README.md
```

## 创建的资源

### 安全组

| 安全组名称 | 用途 |
|-----------|------|
| `{TAG_PREFIX}-studio` | SageMaker Studio 实例 |
| `{TAG_PREFIX}-vpc-endpoints` | VPC Endpoints |

> 注意: AWS 不允许安全组名称以 `sg-` 开头（这是安全组 ID 的保留前缀）

### VPC Endpoints (必需)

| Endpoint | 类型 | 用途 |
|----------|------|------|
| sagemaker.api | Interface | SageMaker API |
| sagemaker.runtime | Interface | SageMaker Runtime |
| sagemaker.studio | Interface | SageMaker Studio (包含 Notebook) |
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

### 必填变量 (在 `.env.local` 中配置)

| 变量 | 说明 | 示例 |
|------|------|------|
| `VPC_ID` | 现有 VPC ID | `vpc-0abc123def456` |
| `VPC_CIDR` | VPC CIDR 范围（用于安全组规则） | `10.0.0.0/16` |
| `PRIVATE_SUBNET_1_ID` | 私有子网 1（AZ-a） | `subnet-0abc123` |
| `PRIVATE_SUBNET_2_ID` | 私有子网 2（AZ-b） | `subnet-0def456` |
| `ROUTE_TABLE_1_ID` | S3 Gateway Endpoint 路由表 | `rtb-0abc123` |

### 可选变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `ROUTE_TABLE_2_ID` | (空) | 第二个路由表（如子网用不同路由表） |
| `CREATE_ECR_ENDPOINTS` | `false` | 创建 ECR Endpoints（拉取自定义镜像） |
| `CREATE_KMS_ENDPOINT` | `false` | 创建 KMS Endpoint（KMS 加密） |
| `CREATE_SSM_ENDPOINT` | `false` | 创建 SSM Endpoint（参数存储） |
| `TAG_PREFIX` | `${COMPANY}-sagemaker` | 资源命名前缀 |

### 从共享配置继承 (在 `../.env.shared` 中)

| 变量 | 说明 |
|------|------|
| `COMPANY` | 公司前缀 |
| `AWS_REGION` | AWS 区域 |
| `AWS_ACCOUNT_ID` | AWS 账号 ID |
| `OUTPUT_DIR` | 输出目录 |

### 查询 AWS 资源的命令

```bash
# 查询 VPC
aws ec2 describe-vpcs --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock}' --output table

# 查询子网
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxx" \
    --query 'Subnets[].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}' --output table

# 查询路由表
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxx" \
    --query 'RouteTables[].{ID:RouteTableId,Associations:Associations[].SubnetId}' --output table
```

## 安全组规则

### {TAG_PREFIX}-studio

**入站规则:**
- All Traffic from self (Studio 内部通信)
- HTTPS (443) from VPC CIDR

**出站规则:**
- All Traffic to self
- HTTPS (443) to 0.0.0.0/0 (默认)

### {TAG_PREFIX}-vpc-endpoints

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
  ✓ acme-sagemaker-studio: sg-0abc123
  ✓ acme-sagemaker-vpc-endpoints: sg-0def456

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
