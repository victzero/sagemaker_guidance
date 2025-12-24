# 05 - SageMaker Domain 设计

> 本文档描述 SageMaker Domain 的创建和配置

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符                 | 说明                    | 示例值                 |
| ---------------------- | ----------------------- | ---------------------- |
| `vpc-xxxxxxxxx`        | VPC ID（待确认）        | `vpc-0abc123def456`    |
| `subnet-a`, `subnet-b` | 子网 ID（待确认）       | `subnet-0abc123def456` |
| `sg-sagemaker-studio`  | 安全组名称              | 按规范创建             |
| `d-xxxxxxxxx`          | Domain ID（创建后获取） | `d-abc123def456`       |

---

## 1. Domain 概述

### 1.1 什么是 Domain

SageMaker Domain 是 SageMaker Studio 的逻辑边界，包含：

- User Profiles（用户配置）
- Shared Spaces（共享空间）
- Apps（应用实例）
- 安全和网络配置

### 1.2 Domain 策略

| 方案                | 优点               | 缺点                     | 选择 |
| ------------------- | ------------------ | ------------------------ | ---- |
| **单一 Domain**     | 管理简单、资源共享 | 需要精细权限控制         | ✅   |
| 多 Domain（每团队） | 隔离彻底           | 管理复杂、无法跨团队协作 | ❌   |

**本项目选择**：单一 Domain，通过 User Profile + Space + IAM 实现隔离

---

## 2. Domain 配置

### 2.1 基础配置

| 配置项                 | 值                         | 说明            |
| ---------------------- | -------------------------- | --------------- |
| Domain Name            | ml-platform-domain         | 平台统一 Domain |
| Auth Mode              | **IAM**                    | 使用 IAM Users  |
| App Network Access     | **VPCOnly**                | 仅 VPC 内访问   |
| Default Execution Role | 无（由 User Profile 指定） | -               |

### 2.2 VPC 配置

| 配置项          | 值                  | 说明            |
| --------------- | ------------------- | --------------- |
| VPC             | vpc-xxxxxxxxx       | 现有 VPC        |
| Subnets         | subnet-a, subnet-b  | Private Subnets |
| Security Groups | sg-sagemaker-studio | Studio 安全组   |

### 2.3 存储配置

| 配置项           | 值       | 说明                       |
| ---------------- | -------- | -------------------------- |
| Default EBS Size | 100 GB   | 默认存储空间（可按需上调） |
| EFS              | 自动创建 | 用于 Studio Home           |

> 说明：EBS 默认值建议以“减少频繁扩容 + 控制成本”为平衡点。实际可配置更大容量，通常受服务配额/区域限制影响，落地前应在目标账号/区域完成一次配置验证。

---

## 3. Domain 网络模式详解

### 3.1 VPCOnly 模式

```
用户浏览器
    │
    │ HTTPS
    ▼
AWS Console
    │
    │ CreatePresignedDomainUrl API
    ▼
Presigned URL
    │
    │ 重定向
    ▼
SageMaker Studio (VPC 内)
    │
    │ ENI in Private Subnet
    ▼
VPC Endpoints → AWS Services
```

### 3.2 网络流量路径

| 流量类型  | 路径                            | 说明          |
| --------- | ------------------------------- | ------------- |
| Studio UI | Console → Presigned URL → VPC   | 通过 AWS 内部 |
| S3 数据   | Studio → S3 VPC Endpoint → S3   | VPC 内部      |
| API 调用  | Studio → SageMaker VPC Endpoint | VPC 内部      |

---

## 4. Default Settings（默认设置）

### 4.1 JupyterLab 默认设置

| 配置项             | 推荐值       | 说明                         |
| ------------------ | ------------ | ---------------------------- |
| Default Instance   | ml.t3.medium | 基础开发                     |
| Auto Shutdown Idle | 60 分钟      | 成本控制                     |
| Lifecycle Config   | **强烈建议** | 启动脚本（含 idle-shutdown） |

> 💡 **成本管控**：强烈建议配置 Lifecycle Configuration 脚本，用于自动检测 Jupyter Kernel 空闲并关闭实例。未配置此脚本可能导致 GPU 实例（如 `ml.g4dn`、`ml.p3`）持续运行产生较高费用。

### 4.2 默认 Space 设置

| 配置项           | 推荐值       | 说明                         |
| ---------------- | ------------ | ---------------------------- |
| Default Instance | ml.t3.medium | 共享空间默认                 |
| EBS Size         | 100 GB       | 默认存储（可按项目申请上调） |

### 4.3 实例规格治理（白名单/上限）

为降低成本风险并提升可控性，建议在“平台策略层”限制 Studio 可用实例规格：

- **白名单**：仅允许指定的 instance types（例如限制在常用家族与固定档位）。
- **上限**：将最大规格限定在某个尺寸（例如不超过 `*4xlarge`），超出需要平台管理员临时放行或审批。
- **强制手段**：以 IAM Policy 对 `CreateApp/UpdateApp` 进行条件约束（比“默认值/推荐值”更具强制力）。

> 验收要点：普通开发者尝试选择超出白名单/上限的实例规格时，应触发 AccessDenied（或在 UI 侧不可见/不可选），确保策略可被证明地执行。

### 4.4 实例白名单策略（参考）

> 说明：以下为“参考白名单”，用于给平台策略提供一个起点。实际应结合区域可用性、配额与成本治理要求进行调整。

| 分层     | 推荐用途                    | 参考白名单（示例）                                             |
| -------- | --------------------------- | -------------------------------------------------------------- |
| 基础开发 | 日常 Notebook、轻量数据处理 | `ml.t3.medium`, `ml.t3.large`, `ml.t3.xlarge`, `ml.t3.2xlarge` |
| 计算密集 | CPU 密集型特征工程/批处理   | `ml.c5.xlarge`, `ml.c5.2xlarge`, `ml.c5.4xlarge`               |

建议同时配置“**最大实例上限**”（例如最大不超过 `*4xlarge`），并对例外使用走审批/临时放行流程。

---

## 5. Domain 创建参数

### 5.1 核心参数

```
Domain 配置:
- DomainName: ml-platform-domain
- AuthMode: IAM
- AppNetworkAccessType: VpcOnly
- VpcId: vpc-xxxxxxxxx
- SubnetIds: [subnet-a, subnet-b]
- DefaultUserSettings:
    - SecurityGroups: [sg-sagemaker-studio]
    - (ExecutionRole 由 User Profile 单独指定)
```

### 5.2 标签

| Tag Key     | Tag Value          |
| ----------- | ------------------ |
| Name        | ml-platform-domain |
| Environment | production         |
| ManagedBy   | platform-team      |

---

## 6. Domain 创建后的资源

Domain 创建后会自动生成以下资源：

| 资源类型       | 名称模式 | 说明           |
| -------------- | -------- | -------------- |
| EFS            | 自动创建 | 用户 Home 目录 |
| Security Group | 自动创建 | EFS 访问 SG    |
| ENI            | 按需创建 | 每个 App 一个  |

---

## 7. 认证流程（IAM 模式）

### 7.1 用户登录流程

```
1. IAM User 登录 AWS Console
   └── 使用用户名/密码 + MFA

2. 导航到 SageMaker → Studio
   └── Console 调用 ListUserProfiles

3. 选择 User Profile
   └── 必须是属于该 IAM User 的 Profile

4. 点击 Open Studio
   └── Console 调用 CreatePresignedDomainUrl

5. 浏览器重定向到 Studio
   └── Presigned URL 有效期 5 分钟

6. Studio 加载
   └── 使用 User Profile 的 Execution Role
```

### 7.2 权限要求

IAM User 需要以下权限才能登录 Studio：

```
必需权限:
- sagemaker:DescribeDomain
- sagemaker:DescribeUserProfile
- sagemaker:CreatePresignedDomainUrl
- sagemaker:ListApps

条件:
- User Profile 必须属于该 IAM User
- User Profile 需要包含正确的 Tags 或命名
```

---

## 8. Domain 管理

### 8.1 生命周期管理

| 操作        | 说明         | 影响           |
| ----------- | ------------ | -------------- |
| 创建 Domain | 初始化平台   | 一次性         |
| 更新 Domain | 修改默认设置 | 不影响现有 App |
| 删除 Domain | 清理所有资源 | **破坏性操作** |

### 8.2 监控指标

| 指标                 | 说明         | 告警阈值     |
| -------------------- | ------------ | ------------ |
| Active User Profiles | 活跃用户数   | -            |
| Running Apps         | 运行中的 App | 根据预算设置 |
| EFS 使用量           | 存储使用     | 80%          |

---

## 9. 与其他资源的关系

### 9.1 依赖关系

```
Domain 依赖:
├── VPC (必须先存在)
├── Subnets (必须先存在)
├── Security Groups (必须先存在)
└── VPC Endpoints (必须先存在)

Domain 被依赖:
├── User Profiles (Domain 创建后)
├── Spaces (Domain 创建后)
└── Apps (Domain 创建后)
```

### 9.2 创建顺序

```
1. VPC 相关 (已存在)
   ├── VPC
   ├── Subnets
   ├── Route Tables
   └── Internet/NAT Gateway

2. 安全相关
   ├── Security Groups
   └── VPC Endpoints

3. IAM 相关
   ├── IAM Policies
   ├── IAM Roles (Execution Roles)
   ├── IAM Groups
   └── IAM Users

4. S3 相关
   └── S3 Buckets

5. SageMaker
   ├── Domain (本文档)
   ├── User Profiles (下一文档)
   └── Spaces (再下一文档)
```

---

## 10. CLI 创建命令

### 10.1 创建 SageMaker Domain

```bash
# 创建 Domain（VPCOnly 模式）
aws sagemaker create-domain \
  --domain-name ml-platform-domain \
  --auth-mode IAM \
  --vpc-id vpc-xxxxxxxxx \
  --subnet-ids subnet-aaaaaaaa subnet-bbbbbbbb \
  --app-network-access-type VpcOnly \
  --default-user-settings '{
    "SecurityGroups": ["sg-sagemaker-studio"]
  }' \
  --default-space-settings '{
    "SecurityGroups": ["sg-sagemaker-studio"]
  }' \
  --tags \
    Key=Name,Value=ml-platform-domain \
    Key=Environment,Value=production \
    Key=ManagedBy,Value=platform-team
```

### 10.2 查询 Domain 状态

```bash
# 获取 Domain ID 和状态
aws sagemaker list-domains

# 详细信息（替换 d-xxxxxxxxx 为实际 Domain ID）
aws sagemaker describe-domain --domain-id d-xxxxxxxxx
```

### 10.3 更新 Domain 设置

```bash
# 更新默认用户设置（如修改默认实例类型）
aws sagemaker update-domain \
  --domain-id d-xxxxxxxxx \
  --default-user-settings '{
    "JupyterLabAppSettings": {
      "DefaultResourceSpec": {
        "InstanceType": "ml.t3.medium"
      }
    }
  }'
```

---

## 11. Lifecycle Configuration 脚本

### 11.1 创建 Lifecycle Config（自动关闭空闲实例）

> 💡 此脚本检测 JupyterLab 空闲状态，超时后自动关闭实例以节省成本。

**步骤 1：创建脚本文件** `auto-shutdown.sh`

```bash
#!/bin/bash
# auto-shutdown.sh - 空闲检测与自动关闭脚本

set -e

# 配置参数
IDLE_TIMEOUT_MINUTES=${IDLE_TIMEOUT_MINUTES:-60}
LOG_FILE="/var/log/auto-shutdown.log"

echo "$(date): Auto-shutdown script started. Idle timeout: ${IDLE_TIMEOUT_MINUTES} minutes" >> $LOG_FILE

# 安装依赖（如果需要）
pip install -q sagemaker-studio-analytics-extension 2>/dev/null || true

# 后台运行空闲检测
nohup bash -c '
IDLE_TIMEOUT_SECONDS=$((IDLE_TIMEOUT_MINUTES * 60))
LAST_ACTIVITY=$(date +%s)

while true; do
    sleep 60

    # 检查是否有活跃的 kernel
    ACTIVE_KERNELS=$(jupyter kernelgateway --list 2>/dev/null | grep -c "running" || echo "0")

    if [ "$ACTIVE_KERNELS" -gt 0 ]; then
        LAST_ACTIVITY=$(date +%s)
    fi

    CURRENT_TIME=$(date +%s)
    IDLE_TIME=$((CURRENT_TIME - LAST_ACTIVITY))

    if [ $IDLE_TIME -gt $IDLE_TIMEOUT_SECONDS ]; then
        echo "$(date): Idle timeout reached. Shutting down..." >> /var/log/auto-shutdown.log

        # 调用 SageMaker API 关闭 App
        aws sagemaker delete-app \
            --domain-id $DOMAIN_ID \
            --user-profile-name $USER_PROFILE_NAME \
            --app-type JupyterLab \
            --app-name default 2>/dev/null || true

        break
    fi
done
' &

echo "$(date): Auto-shutdown monitor started in background" >> $LOG_FILE
```

**步骤 2：Base64 编码并创建 Lifecycle Config**

```bash
# 编码脚本
LCC_CONTENT=$(cat auto-shutdown.sh | base64 -w 0)

# 创建 Lifecycle Configuration
aws sagemaker create-studio-lifecycle-config \
  --studio-lifecycle-config-name auto-shutdown-60min \
  --studio-lifecycle-config-app-type JupyterLab \
  --studio-lifecycle-config-content "$LCC_CONTENT"
```

**步骤 3：绑定到 Domain（应用于所有用户）**

```bash
aws sagemaker update-domain \
  --domain-id d-xxxxxxxxx \
  --default-user-settings '{
    "JupyterLabAppSettings": {
      "DefaultResourceSpec": {
        "InstanceType": "ml.t3.medium",
        "LifecycleConfigArn": "arn:aws:sagemaker:{region}:{account-id}:studio-lifecycle-config/auto-shutdown-60min"
      },
      "LifecycleConfigArns": [
        "arn:aws:sagemaker:{region}:{account-id}:studio-lifecycle-config/auto-shutdown-60min"
      ]
    }
  }'
```

### 11.2 简化版：使用 AWS 官方扩展

> AWS 提供了官方的 SageMaker Studio 自动关闭扩展，可作为替代方案。

```bash
# 在 JupyterLab 中安装（用户手动或通过 Lifecycle Config）
pip install sagemaker-studio-auto-shutdown-extension

# 配置空闲超时（分钟）
jupyter server extension enable --py sagemaker_studio_auto_shutdown
```

---

## 12. EFS 加密配置

### 12.1 SageMaker 自动创建的 EFS

Domain 创建时会自动生成 EFS 文件系统用于 Home 目录：

| 配置项     | 默认值              | 说明               |
| ---------- | ------------------- | ------------------ |
| 加密       | **默认启用（SSE）** | 使用 AWS 托管密钥  |
| 性能模式   | General Purpose     | 适合大多数工作负载 |
| 吞吐量模式 | Bursting            | 按需扩展           |

> 📌 SageMaker 自动创建的 EFS 默认启用加密（SSE），使用 `aws/elasticfilesystem` 托管密钥。如需使用 CMK，需在 Domain 创建前准备。

### 12.2 使用自定义 KMS Key 加密 EFS（可选）

如需更严格的密钥管理，可在创建 Domain 时指定 KMS Key：

```bash
aws sagemaker create-domain \
  --domain-name ml-platform-domain \
  --auth-mode IAM \
  --vpc-id vpc-xxxxxxxxx \
  --subnet-ids subnet-aaaaaaaa subnet-bbbbbbbb \
  --app-network-access-type VpcOnly \
  --home-efs-file-system-kms-key-id arn:aws:kms:{region}:{account-id}:key/{key-id} \
  --default-user-settings '{
    "SecurityGroups": ["sg-sagemaker-studio"]
  }' \
  --tags Key=Name,Value=ml-platform-domain
```

### 12.3 验证 EFS 加密状态

```bash
# 获取 Domain 关联的 EFS ID
DOMAIN_INFO=$(aws sagemaker describe-domain --domain-id d-xxxxxxxxx)
EFS_ID=$(echo $DOMAIN_INFO | jq -r '.HomeEfsFileSystemId')

# 检查 EFS 加密配置
aws efs describe-file-systems --file-system-id $EFS_ID \
  --query 'FileSystems[0].{Encrypted:Encrypted,KmsKeyId:KmsKeyId}'
```

---

## 13. 自定义镜像配置（可选）

### 13.1 适用场景

| 场景          | 说明                                | 建议         |
| ------------- | ----------------------------------- | ------------ |
| 预装特定库    | 团队通用依赖（如 PyTorch 特定版本） | 按需配置     |
| 合规/安全加固 | 移除不必要组件、加固系统            | 按需配置     |
| 离线/内网环境 | 所有依赖打包进镜像                  | 按需配置     |
| 一般开发      | 使用 SageMaker 官方镜像             | **默认即可** |

### 13.2 创建自定义镜像

**步骤 1：准备 Dockerfile**

```dockerfile
# 基于 SageMaker 官方 JupyterLab 镜像
FROM 763104351884.dkr.ecr.{region}.amazonaws.com/pytorch-training:2.0.1-gpu-py310-cu118-ubuntu20.04-sagemaker

# 安装团队通用依赖
RUN pip install --no-cache-dir \
    pandas==2.0.3 \
    scikit-learn==1.3.0 \
    xgboost==1.7.6 \
    lightgbm==4.0.0

# 配置环境
ENV TEAM_NAME="ml-platform"
```

**步骤 2：构建并推送到 ECR**

```bash
# 登录 ECR
aws ecr get-login-password --region {region} | \
  docker login --username AWS --password-stdin {account-id}.dkr.ecr.{region}.amazonaws.com

# 创建 ECR 仓库
aws ecr create-repository --repository-name sagemaker-custom-image

# 构建并推送
docker build -t sagemaker-custom-image:latest .
docker tag sagemaker-custom-image:latest {account-id}.dkr.ecr.{region}.amazonaws.com/sagemaker-custom-image:latest
docker push {account-id}.dkr.ecr.{region}.amazonaws.com/sagemaker-custom-image:latest
```

**步骤 3：创建 SageMaker Image**

```bash
# 创建 Image
aws sagemaker create-image \
  --image-name ml-platform-custom \
  --role-arn arn:aws:iam::{account-id}:role/SageMakerImageRole

# 创建 Image Version
aws sagemaker create-image-version \
  --image-name ml-platform-custom \
  --base-image {account-id}.dkr.ecr.{region}.amazonaws.com/sagemaker-custom-image:latest

# 创建 App Image Config
aws sagemaker create-app-image-config \
  --app-image-config-name ml-platform-custom-config \
  --jupyter-lab-app-image-config '{
    "FileSystemConfig": {
      "MountPath": "/home/sagemaker-user",
      "DefaultUid": 1000,
      "DefaultGid": 100
    }
  }'
```

**步骤 4：关联到 Domain**

```bash
aws sagemaker update-domain \
  --domain-id d-xxxxxxxxx \
  --default-user-settings '{
    "JupyterLabAppSettings": {
      "CustomImages": [
        {
          "ImageName": "ml-platform-custom",
          "AppImageConfigName": "ml-platform-custom-config"
        }
      ]
    }
  }'
```

---

## 14. 检查清单

### 创建前

- [ ] 确认 VPC 和 Subnet 信息
- [ ] 创建 Security Group
- [ ] 创建 VPC Endpoints
- [ ] 确认 IAM Roles 已创建

### 创建时

- [ ] 使用 IAM 认证模式
- [ ] 选择 VPCOnly 网络模式
- [ ] 配置正确的 Subnets
- [ ] 配置正确的 Security Groups

### 创建后

- [ ] 验证 Domain 状态为 InService
- [ ] 验证 EFS 创建成功
- [ ] 记录 Domain ID
- [ ] 开始创建 User Profiles
