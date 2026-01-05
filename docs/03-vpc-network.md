# 03 - VPC 网络配置

> 本文档描述使用现有 VPC 部署 SageMaker 的网络配置

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符             | 说明                | 示例值                 |
| ------------------ | ------------------- | ---------------------- |
| `{region}`         | AWS 区域            | `ap-southeast-1`       |
| `vpc-xxxxxxxxx`    | VPC ID（待确认）    | `vpc-0abc123def456`    |
| `subnet-xxxxxxxxx` | 子网 ID（待确认）   | `subnet-0abc123def456` |
| `sg-xxxxxxxxx`     | 安全组 ID（待确认） | `sg-0abc123def456`     |
| `vpce-xxxxxxxx`    | VPC Endpoint ID     | `vpce-0abc123def456`   |
| `10.x.x.x/xx`      | CIDR 范围（待确认） | `10.0.1.0/24`          |
| `ap-xxx-1a`        | 可用区（待确认）    | `ap-southeast-1a`      |

---

## 1. 前提条件

### 1.1 现有 VPC 要求

| 要求            | 说明                              | 检查项 |
| --------------- | --------------------------------- | ------ |
| Private Subnets | 2-3 个可用区（支持 2 或 3 个子网）| ☐      |
| DNS 解析        | enableDnsHostnames = true         | ☐      |
| DNS 支持        | enableDnsSupport = true           | ☐      |
| CIDR 空间       | 足够的 IP 地址（每子网 128+ IPs） | ☐      |
| 路由表          | 1-3 个路由表（用于 S3 Gateway）   | ☐      |

### 1.2 网络模式选择

| 模式               | 说明               | 适用场景        |
| ------------------ | ------------------ | --------------- |
| **VPCOnly**        | 所有流量走 VPC     | ✅ 生产环境推荐 |
| PublicInternetOnly | 通过 Internet 访问 | 开发测试        |

**本项目选择：VPCOnly**

---

## 2. 子网规划

### 2.1 子网要求

SageMaker Studio 需要在 **Private Subnet** 中运行：

```
VPC: vpc-xxxxxxxxx (现有)
│
├── Private Subnet A (ap-xxx-1a)
│   ├── 用于: SageMaker Studio ENI
│   └── 要求: 足够 IP（每用户约 2-4 个 ENI）
│
├── Private Subnet B (ap-xxx-1b)
│   ├── 用于: SageMaker Studio ENI (高可用)
│   └── 要求: 足够 IP
│
└── [其他现有子网...]
```

### 2.2 IP 地址规划

| 团队/项目 | 预估用户  | ENI 需求  | 建议预留 IP   |
| --------- | --------- | --------- | ------------- |
| 风控团队  | 6-9 人    | 12-36     | 50            |
| 算法团队  | 6-9 人    | 12-36     | 50            |
| 缓冲      | -         | -         | 28            |
| **总计**  | **12-18** | **24-72** | **128 (/25)** |

### 2.3 子网选择清单

| 配置项        | 值               | 备注         |
| ------------- | ---------------- | ------------ |
| Subnet 1 ID   | subnet-xxxxxxxxx | AZ-a（必需） |
| Subnet 2 ID   | subnet-yyyyyyyyy | AZ-b（必需） |
| Subnet 3 ID   | subnet-zzzzzzzzz | AZ-c（可选） |
| Subnet CIDR 1 | 10.x.x.0/24      | 待确认       |
| Subnet CIDR 2 | 10.x.x.0/24      | 待确认       |
| Subnet CIDR 3 | 10.x.x.0/24      | 待确认       |

> **注意**：脚本支持 2-3 个子网配置。第三个子网 (`PRIVATE_SUBNET_3_ID`) 为可选。

---

## 3. 安全组设计

> 📌 安全组命名格式：`{TAG_PREFIX}-{用途}`，其中 `TAG_PREFIX` 默认为 `{COMPANY}-sagemaker`
>
> 示例：`acme-sagemaker-studio`、`acme-sagemaker-training`

### 3.1 安全组概览

| 安全组名称                 | 类型     | 用途                              |
| -------------------------- | -------- | --------------------------------- |
| `{TAG_PREFIX}-studio`      | 核心     | SageMaker Studio 实例             |
| `{TAG_PREFIX}-vpc-endpoints` | 核心   | VPC Endpoints                     |
| `{TAG_PREFIX}-training`    | 工作负载 | Training Jobs (分布式训练)        |
| `{TAG_PREFIX}-processing`  | 工作负载 | Processing Jobs (Spark 集群)      |
| `{TAG_PREFIX}-inference`   | 工作负载 | Inference Endpoints (推理服务)    |

> **注意**: AWS 不允许安全组名称以 `sg-` 开头（这是安全组 ID 的保留前缀）

### 3.2 SageMaker Studio 安全组（核心）

**名称**: `{TAG_PREFIX}-studio`

#### 入站规则 (Inbound)

| 类型        | 协议 | 端口范围 | 来源     | 说明            |
| ----------- | ---- | -------- | -------- | --------------- |
| All Traffic | All  | All      | 自身 SG  | Studio 内部通信 |
| HTTPS       | TCP  | 443      | VPC CIDR | API 访问        |

#### 出站规则 (Outbound)

| 类型        | 协议 | 端口范围 | 目标      | 说明            |
| ----------- | ---- | -------- | --------- | --------------- |
| HTTPS       | TCP  | 443      | 0.0.0.0/0 | AWS 服务访问    |
| All Traffic | All  | All      | 自身 SG   | Studio 内部通信 |

### 3.3 VPC Endpoints 安全组（核心）

**名称**: `{TAG_PREFIX}-vpc-endpoints`

#### 入站规则 (Inbound)

| 类型  | 协议 | 端口范围 | 来源     | 说明            |
| ----- | ---- | -------- | -------- | --------------- |
| HTTPS | TCP  | 443      | VPC CIDR | 允许 VPC 内访问 |

### 3.4 Training Jobs 安全组（工作负载）

**名称**: `{TAG_PREFIX}-training`

用于分布式训练作业，需要节点间通信。

#### 入站规则 (Inbound)

| 类型        | 协议 | 端口范围 | 来源     | 说明                     |
| ----------- | ---- | -------- | -------- | ------------------------ |
| All Traffic | All  | All      | 自身 SG  | 分布式训练节点间通信     |
| HTTPS       | TCP  | 443      | VPC CIDR | API 访问                 |

#### 出站规则 (Outbound)

| 类型        | 协议 | 端口范围 | 目标      | 说明                 |
| ----------- | ---- | -------- | --------- | -------------------- |
| All Traffic | All  | All      | 自身 SG   | 分布式训练节点间通信 |
| HTTPS       | TCP  | 443      | 0.0.0.0/0 | AWS 服务访问（默认） |

### 3.5 Processing Jobs 安全组（工作负载）

**名称**: `{TAG_PREFIX}-processing`

用于 Processing Jobs 和 Spark 集群，需要节点间通信。

#### 入站规则 (Inbound)

| 类型        | 协议 | 端口范围 | 来源     | 说明                 |
| ----------- | ---- | -------- | -------- | -------------------- |
| All Traffic | All  | All      | 自身 SG  | Spark 集群节点间通信 |
| HTTPS       | TCP  | 443      | VPC CIDR | API 访问             |

#### 出站规则 (Outbound)

| 类型        | 协议 | 端口范围 | 目标      | 说明                 |
| ----------- | ---- | -------- | --------- | -------------------- |
| All Traffic | All  | All      | 自身 SG   | Spark 集群节点间通信 |
| HTTPS       | TCP  | 443      | 0.0.0.0/0 | AWS 服务访问（默认） |

### 3.6 Inference Endpoints 安全组（工作负载）

**名称**: `{TAG_PREFIX}-inference`

用于实时推理端点和批量转换。

#### 入站规则 (Inbound)

| 类型  | 协议 | 端口范围 | 来源     | 说明             |
| ----- | ---- | -------- | -------- | ---------------- |
| HTTPS | TCP  | 443      | VPC CIDR | 推理请求         |
| TCP   | TCP  | 8080     | VPC CIDR | 推理容器端口     |

#### 出站规则 (Outbound)

| 类型  | 协议 | 端口范围 | 目标      | 说明                 |
| ----- | ---- | -------- | --------- | -------------------- |
| HTTPS | TCP  | 443      | 0.0.0.0/0 | AWS 服务访问（默认） |

---

## 4. VPC Endpoints

### 4.1 必需的 Endpoints

SageMaker Studio (VPCOnly 模式) 需要以下 Endpoints：

| Endpoint 类型     | Service Name                             | 类型      | 必需 |
| ----------------- | ---------------------------------------- | --------- | ---- |
| SageMaker API     | com.amazonaws.{region}.sagemaker.api     | Interface | ✅   |
| SageMaker Runtime | com.amazonaws.{region}.sagemaker.runtime | Interface | ✅   |
| SageMaker Studio  | **aws.sagemaker.{region}.studio**        | Interface | ✅   |
| STS               | com.amazonaws.{region}.sts               | Interface | ✅   |
| S3                | com.amazonaws.{region}.s3                | Gateway   | ✅   |
| CloudWatch Logs   | com.amazonaws.{region}.logs              | Interface | ✅   |

### 4.2 可选但推荐的 Endpoints

| Endpoint 类型   | Service Name                           | 类型      | 用途                            | 环境变量                     |
| --------------- | -------------------------------------- | --------- | ------------------------------- | ---------------------------- |
| ECR API         | com.amazonaws.{region}.ecr.api         | Interface | 拉取容器镜像                    | `CREATE_ECR_ENDPOINTS=true`  |
| ECR DKR         | com.amazonaws.{region}.ecr.dkr         | Interface | 拉取容器镜像                    | `CREATE_ECR_ENDPOINTS=true`  |
| KMS             | com.amazonaws.{region}.kms             | Interface | 数据加密                        | `CREATE_KMS_ENDPOINT=true`   |
| SSM             | com.amazonaws.{region}.ssm             | Interface | 配置管理                        | `CREATE_SSM_ENDPOINT=true`   |
| Bedrock Runtime | com.amazonaws.{region}.bedrock-runtime | Interface | Canvas AI 功能 (Chat for data) | `CREATE_BEDROCK_ENDPOINT=true` |

> ⚠️ **SageMaker Canvas 用户注意**: 如需在 VPCOnly 模式下使用 Canvas 的 AI 功能（如 Chat for data prep、AI-powered insights），**必须**创建 Bedrock Runtime endpoint。否则 Canvas 控制台会显示警告：*"The selected VPC is not connected to Amazon Bedrock"*

### 4.3 Gateway vs Interface Endpoint：为什么 S3 使用 Gateway？

> 📌 **AWS 官方推荐：对于 S3 和 DynamoDB，优先使用 Gateway Endpoint**

#### 两种 Endpoint 类型对比

| 特性         | Gateway Endpoint           | Interface Endpoint (PrivateLink) |
| ------------ | -------------------------- | -------------------------------- |
| **费用**     | 🆓 **免费**                | 💰 ~$7.2/月 + 数据传输费         |
| **网络路径** | 通过路由表直接路由到 S3    | 通过 ENI (弹性网卡) 转发         |
| **带宽**     | **无限制** (AWS 骨干网)    | 受 ENI 带宽限制                  |
| **延迟**     | 更低                       | 略高 (多一跳)                    |
| **DNS**      | 使用公共 S3 DNS            | 私有 DNS                         |
| **跨区域**   | ❌ 仅限同区域              | ❌ 仅限同区域                    |
| **支持服务** | 仅 S3、DynamoDB            | 大多数 AWS 服务                  |

#### 架构对比图

```
Gateway Endpoint (推荐用于 S3):
┌─────────────────────────────────────────────────────────────┐
│  VPC                                                        │
│  ┌─────────────┐       ┌─────────────────┐                 │
│  │  SageMaker  │──────▶│  Route Table    │────────────────┼──▶ S3
│  │   Studio    │       │  (pl-xxxxxx)    │  Gateway       │
│  └─────────────┘       └─────────────────┘  Endpoint      │
└─────────────────────────────────────────────────────────────┘
                          直接路由，无 ENI，无带宽限制

Interface Endpoint (PrivateLink):
┌─────────────────────────────────────────────────────────────┐
│  VPC                                                        │
│  ┌─────────────┐       ┌─────────────────┐                 │
│  │  SageMaker  │──────▶│  ENI (vpce-xxx) │────────────────┼──▶ S3
│  │   Studio    │       │  10.0.1.x       │  PrivateLink   │
│  └─────────────┘       └─────────────────┘                 │
└─────────────────────────────────────────────────────────────┘
                          需要 ENI，有带宽限制
```

#### 选型决策表

| 场景                             | 推荐类型      | 原因                               |
| -------------------------------- | ------------- | ---------------------------------- |
| 访问 S3（高吞吐数据处理）        | ✅ **Gateway** | 免费、高性能、无带宽限制           |
| 访问 S3（跨账户私有链接）        | Interface     | Gateway 不支持跨账户策略           |
| 从 on-premises 通过 VPN 访问 S3  | Interface     | Gateway 路由不能传播到 on-premises |
| 访问 SageMaker API               | Interface     | 无 Gateway 选项                    |
| 访问 CloudWatch Logs             | Interface     | 无 Gateway 选项                    |
| 访问 ECR                         | Interface     | 无 Gateway 选项                    |

#### 本项目 Endpoint 类型选择

| 服务              | Endpoint 类型   | 选择原因                     |
| ----------------- | --------------- | ---------------------------- |
| S3                | **Gateway**     | 免费、高性能、SageMaker 大量数据读写 |
| SageMaker API     | Interface       | 只有此选项                   |
| SageMaker Runtime | Interface       | 只有此选项                   |
| SageMaker Studio  | Interface       | 只有此选项                   |
| STS               | Interface       | 只有此选项                   |
| CloudWatch Logs   | Interface       | 只有此选项                   |
| ECR (可选)        | Interface       | 只有此选项                   |

### 4.4 Endpoint 配置清单

| Endpoint          | Subnet             | 安全组           | Policy | 状态     |
| ----------------- | ------------------ | ---------------- | ------ | -------- |
| sagemaker.api     | subnet-a, subnet-b | sg-vpc-endpoints | 默认   | ☐ 待创建 |
| sagemaker.runtime | subnet-a, subnet-b | sg-vpc-endpoints | 默认   | ☐ 待创建 |
| sagemaker.studio  | subnet-a, subnet-b | sg-vpc-endpoints | 默认   | ☐ 待创建 |
| sts               | subnet-a, subnet-b | sg-vpc-endpoints | 默认   | ☐ 待创建 |
| s3 (Gateway)      | -                  | -                | 默认   | ☐ 待创建 |
| logs              | subnet-a, subnet-b | sg-vpc-endpoints | 默认   | ☐ 待创建 |

---

## 5. 路由表配置

### 5.1 Private Subnet 路由表

| 目标           | 目标类型      | 说明                 |
| -------------- | ------------- | -------------------- |
| VPC CIDR       | local         | 本地路由             |
| S3 Prefix List | vpce-xxxxxxxx | S3 Gateway Endpoint  |
| 0.0.0.0/0      | NAT Gateway   | (可选) Internet 出口 |

### 5.2 S3 Gateway Endpoint 路由

S3 Gateway Endpoint 会自动添加路由到关联的路由表：

```
目标: pl-xxxxxxxx (S3 Prefix List)
下一跳: vpce-xxxxxxxx (S3 Gateway Endpoint)
```

---

## 6. 网络流量路径

### 6.1 Studio 访问路径

```
用户浏览器
    │
    │ HTTPS (443)
    ▼
AWS Console / Presigned URL
    │
    │ AWS 内部路由
    ▼
VPC Endpoint (sagemaker.studio)
    │
    │ VPC 内部
    ▼
SageMaker Studio (Private Subnet)
```

### 6.2 数据访问路径

```
SageMaker Notebook
    │
    │ S3 API 调用
    ▼
VPC Endpoint (S3 Gateway)
    │
    │ AWS 内部骨干网
    ▼
S3 Bucket
```

---

## 6A. VPCOnly 下依赖安装与出网策略（验收高风险点）

> 目标：在 VPCOnly 模式下，让 Notebook“可控地”获得依赖（pip/conda/apt 等）与外部资源访问能力，并形成可验收的网络与安全边界。

### 6A.1 三种常见策略（从宽到严）

| 策略                        | 网络形态                              | 适用          | 主要风险/代价         |
| --------------------------- | ------------------------------------- | ------------- | --------------------- |
| **A. 允许出网**             | Private Subnet → NAT → Internet       | 交付速度优先  | 出网治理与供应链风险  |
| **B. 受控出网（推荐）**     | NAT + 代理/防火墙 + 域名/目的地白名单 | 生产常见做法  | 需要维护 allowlist    |
| **C. 禁止出网（内网依赖）** | 无 NAT；仅 VPC Endpoints + 内部制品库 | 高合规/高管控 | 需要提前准备镜像/制品 |

### 6A.2 依赖获取的落地方式（与策略配套）

- **预构建环境**：通过自定义镜像（ECR）或受控的基线镜像，把常用依赖预装，减少运行时下载。
- **内部制品库**（策略 B/C 重点）：
  - Python：内部 PyPI/缓存（或使用 AWS CodeArtifact）
  - Conda：内部 channel mirror
  - OS 包：内部镜像源/仓库代理
- **VPC Endpoints 完整性**：在无/受控出网模式下，优先通过 Endpoints 访问 S3、ECR、CloudWatch、STS、KMS 等 AWS 服务。

### 6A.3 验收检查（建议必测）

- **依赖安装**：在 Notebook 内安装/导入常用依赖（按贵司基线清单），预期成功。
- **出网边界**：
  - 策略 A：可访问公网（明确范围）。
  - 策略 B：仅允许访问白名单目的地，非白名单应失败。
  - 策略 C：访问公网应失败，但访问 AWS Endpoints/内部制品库应成功。
- **可观测性**：可定位失败原因（DNS/路由/SG/NACL/Endpoint/代理策略）。

---

## 7. 待确认信息

### 7.1 现有 VPC 信息

| 项目          | 值             | 状态     |
| ------------- | -------------- | -------- |
| VPC ID        | vpc-xxxxxxxxx  | ☐ 待确认 |
| VPC CIDR      | 10.x.x.x/16    | ☐ 待确认 |
| Region        | ap-southeast-1 | ☐ 待确认 |
| DNS Hostnames | true           | ☐ 待确认 |
| DNS Support   | true           | ☐ 待确认 |

### 7.2 子网信息

| 项目                  | 值               | 状态     |
| --------------------- | ---------------- | -------- |
| Private Subnet 1 ID   | subnet-xxxxxxxxx | ☐ 待确认 |
| Private Subnet 1 CIDR | 10.x.x.x/24      | ☐ 待确认 |
| Private Subnet 1 AZ   | ap-xxx-1a        | ☐ 待确认 |
| Private Subnet 2 ID   | subnet-yyyyyyyyy | ☐ 待确认 |
| Private Subnet 2 CIDR | 10.x.x.x/24      | ☐ 待确认 |
| Private Subnet 2 AZ   | ap-xxx-1b        | ☐ 待确认 |

### 7.3 现有安全组检查

| 检查项                     | 状态     |
| -------------------------- | -------- |
| 是否有可复用的 Endpoint SG | ☐ 待确认 |
| 现有 SG 规则是否冲突       | ☐ 待确认 |

---

## 8. 检查清单

### 部署前

- [ ] 确认 VPC 信息（VPC ID, CIDR）
- [ ] 确认子网信息（2-3 个 Private Subnets）
- [ ] 确认路由表（1-3 个，用于 S3 Gateway Endpoint）
- [ ] 计算 IP 地址需求（每子网 128+ IPs）
- [ ] 确认现有 VPC Endpoints

### 部署中

- [ ] 创建核心安全组 `{TAG_PREFIX}-studio`
- [ ] 创建核心安全组 `{TAG_PREFIX}-vpc-endpoints`
- [ ] 创建工作负载安全组 `{TAG_PREFIX}-training`
- [ ] 创建工作负载安全组 `{TAG_PREFIX}-processing`
- [ ] 创建工作负载安全组 `{TAG_PREFIX}-inference`
- [ ] 创建必需的 VPC Endpoints（6 个）
- [ ] 创建可选的 VPC Endpoints（按需：ECR, KMS, SSM, Bedrock）
- [ ] 验证路由表配置

### 部署后

- [ ] 测试 Studio 连接
- [ ] 测试 S3 访问
- [ ] 测试 ECR 访问（如需要）
- [ ] 测试 Canvas AI 功能（如启用 Bedrock）

---

## 9. 实现脚本

VPC 配置由自动化脚本实现，详见 [scripts/02-vpc/README.md](../scripts/02-vpc/README.md)。

### 脚本清单

| 脚本                           | 用途                                |
| ------------------------------ | ----------------------------------- |
| `00-init.sh`                   | 初始化和环境变量验证                |
| `01-create-security-groups.sh` | 创建核心安全组 (Studio + Endpoints) |
| `02-create-vpc-endpoints.sh`   | 创建 VPC Endpoints                  |
| `03-create-workload-sgs.sh`    | 创建工作负载安全组                  |
| `setup-all.sh`                 | 一次性创建所有资源                  |
| `verify.sh`                    | 验证配置                            |
| `cleanup.sh`                   | 清理资源                            |

### 环境变量

| 变量                    | 说明                   | 必需 |
| ----------------------- | ---------------------- | ---- |
| `VPC_ID`                | 现有 VPC ID            | ✅   |
| `VPC_CIDR`              | VPC CIDR 范围          | ✅   |
| `PRIVATE_SUBNET_1_ID`   | 私有子网 1 (AZ-a)      | ✅   |
| `PRIVATE_SUBNET_2_ID`   | 私有子网 2 (AZ-b)      | ✅   |
| `PRIVATE_SUBNET_3_ID`   | 私有子网 3 (AZ-c)      | ❌   |
| `ROUTE_TABLE_1_ID`      | 路由表 1               | ✅   |
| `ROUTE_TABLE_2_ID`      | 路由表 2               | ❌   |
| `ROUTE_TABLE_3_ID`      | 路由表 3               | ❌   |
| `CREATE_ECR_ENDPOINTS`  | 创建 ECR Endpoints     | ❌   |
| `CREATE_KMS_ENDPOINT`   | 创建 KMS Endpoint      | ❌   |
| `CREATE_SSM_ENDPOINT`   | 创建 SSM Endpoint      | ❌   |
| `CREATE_BEDROCK_ENDPOINT` | 创建 Bedrock Endpoint (Canvas AI) | ❌ |
