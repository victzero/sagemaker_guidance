# 05 - SageMaker Domain 设计

> 本文档描述 SageMaker Domain 的创建和配置

---

## 1. Domain 概述

### 1.1 什么是 Domain

SageMaker Domain 是 SageMaker Studio 的逻辑边界，包含：
- User Profiles（用户配置）
- Shared Spaces（共享空间）
- Apps（应用实例）
- 安全和网络配置

### 1.2 Domain 策略

| 方案 | 优点 | 缺点 | 选择 |
|------|------|------|------|
| **单一 Domain** | 管理简单、资源共享 | 需要精细权限控制 | ✅ |
| 多 Domain（每团队） | 隔离彻底 | 管理复杂、无法跨团队协作 | ❌ |

**本项目选择**：单一 Domain，通过 User Profile + Space + IAM 实现隔离

---

## 2. Domain 配置

### 2.1 基础配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| Domain Name | ml-platform-domain | 平台统一 Domain |
| Auth Mode | **IAM** | 使用 IAM Users |
| App Network Access | **VPCOnly** | 仅 VPC 内访问 |
| Default Execution Role | 无（由 User Profile 指定） | - |

### 2.2 VPC 配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| VPC | vpc-xxxxxxxxx | 现有 VPC |
| Subnets | subnet-a, subnet-b | Private Subnets |
| Security Groups | sg-sagemaker-studio | Studio 安全组 |

### 2.3 存储配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| Default EBS Size | 20 GB | 默认存储空间 |
| EFS | 自动创建 | 用于 Studio Home |

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

| 流量类型 | 路径 | 说明 |
|----------|------|------|
| Studio UI | Console → Presigned URL → VPC | 通过 AWS 内部 |
| S3 数据 | Studio → S3 VPC Endpoint → S3 | VPC 内部 |
| API 调用 | Studio → SageMaker VPC Endpoint | VPC 内部 |

---

## 4. Default Settings（默认设置）

### 4.1 JupyterLab 默认设置

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| Default Instance | ml.t3.medium | 基础开发 |
| Auto Shutdown Idle | 60 分钟 | 成本控制 |
| Lifecycle Config | 可选 | 启动脚本 |

### 4.2 默认 Space 设置

| 配置项 | 推荐值 | 说明 |
|--------|--------|------|
| Default Instance | ml.t3.medium | 共享空间默认 |
| EBS Size | 20 GB | 默认存储 |

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

| Tag Key | Tag Value |
|---------|-----------|
| Name | ml-platform-domain |
| Environment | production |
| ManagedBy | platform-team |

---

## 6. Domain 创建后的资源

Domain 创建后会自动生成以下资源：

| 资源类型 | 名称模式 | 说明 |
|----------|----------|------|
| EFS | 自动创建 | 用户 Home 目录 |
| Security Group | 自动创建 | EFS 访问 SG |
| ENI | 按需创建 | 每个 App 一个 |

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

| 操作 | 说明 | 影响 |
|------|------|------|
| 创建 Domain | 初始化平台 | 一次性 |
| 更新 Domain | 修改默认设置 | 不影响现有 App |
| 删除 Domain | 清理所有资源 | **破坏性操作** |

### 8.2 监控指标

| 指标 | 说明 | 告警阈值 |
|------|------|----------|
| Active User Profiles | 活跃用户数 | - |
| Running Apps | 运行中的 App | 根据预算设置 |
| EFS 使用量 | 存储使用 | 80% |

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

## 10. 待完善内容

- [ ] 完整的 CLI/CloudFormation 创建命令
- [ ] Lifecycle Configuration 脚本
- [ ] EFS 加密配置
- [ ] 自定义镜像配置

---

## 11. 检查清单

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

