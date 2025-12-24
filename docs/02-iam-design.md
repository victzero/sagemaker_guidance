# 02 - IAM 权限设计

> 本文档描述 IAM Groups / Users / Roles / Policies 的设计

---

## 1. IAM 资源概览

### 1.1 资源清单

| 类型         | 数量   | 说明                  |
| ------------ | ------ | --------------------- |
| IAM Groups   | ~6-8   | 2 团队组 + 4-6 项目组 |
| IAM Users    | ~12-18 | 每项目 2-3 人         |
| IAM Roles    | ~4-6   | 每项目 1 个执行角色   |
| IAM Policies | ~8-12  | 基础策略 + 项目策略   |

### 1.2 设计原则

1. **最小权限**：只授予必要的权限
2. **职责分离**：管理员与开发者权限分开
3. **基于角色**：通过 Group 管理权限，避免直接给 User 授权
4. **可审计**：便于权限审计和变更追踪

---

## 2. IAM Groups 设计

### 2.1 Group 层级

```
IAM Groups
│
├── 平台级
│   ├── sagemaker-admins          # 平台管理员
│   └── sagemaker-readonly        # 只读查看者
│
├── 团队级
│   ├── sagemaker-risk-control    # 风控团队（所有成员）
│   └── sagemaker-algorithm       # 算法团队（所有成员）
│
└── 项目级
    ├── sagemaker-rc-project-a    # 风控项目A
    ├── sagemaker-rc-project-b    # 风控项目B
    ├── sagemaker-algo-project-x  # 算法项目X
    └── sagemaker-algo-project-y  # 算法项目Y
```

### 2.2 Group 职责

| Group                        | 职责              | 典型权限              |
| ---------------------------- | ----------------- | --------------------- |
| `sagemaker-admins`           | Domain/Space 管理 | Full SageMaker Admin  |
| `sagemaker-readonly`         | 监控、审计        | Describe/List only    |
| `sagemaker-{team}`           | 团队通用权限      | Studio 登录、基础操作 |
| `sagemaker-{team}-{project}` | 项目数据访问      | 项目 S3 + Space 权限  |

### 2.3 用户 Group 关系

每个用户属于**多个 Group**（权限叠加）：

```
用户: sm-rc-alice
├── sagemaker-risk-control      # 团队组（基础权限）
└── sagemaker-rc-project-a      # 项目组（项目权限）

用户: sm-algo-frank
├── sagemaker-algorithm         # 团队组（基础权限）
└── sagemaker-algo-project-x    # 项目组（项目权限）
```

---

## 3. IAM Users 设计

### 3.1 User 命名规范

| 团队     | 命名模式          | 示例                         |
| -------- | ----------------- | ---------------------------- |
| 风控团队 | `sm-rc-{name}`    | sm-rc-alice, sm-rc-bob       |
| 算法团队 | `sm-algo-{name}`  | sm-algo-frank, sm-algo-grace |
| 管理员   | `sm-admin-{name}` | sm-admin-jason               |

### 3.2 User 属性配置

| 属性                | 配置    | 说明                 |
| ------------------- | ------- | -------------------- |
| Console Access      | ✅ 启用 | 需要登录 AWS Console |
| Programmatic Access | ⚠️ 按需 | API/CLI 访问         |
| MFA                 | ✅ 强制 | 安全要求             |
| Password Policy     | 强密码  | 遵循公司策略         |

### 3.3 User 清单模板

| User          | 团队 | 项目      | Groups                     |
| ------------- | ---- | --------- | -------------------------- |
| sm-rc-alice   | 风控 | project-a | risk-control, rc-project-a |
| sm-rc-bob     | 风控 | project-a | risk-control, rc-project-a |
| sm-rc-carol   | 风控 | project-a | risk-control, rc-project-a |
| sm-rc-david   | 风控 | project-b | risk-control, rc-project-b |
| sm-rc-emma    | 风控 | project-b | risk-control, rc-project-b |
| sm-algo-frank | 算法 | project-x | algorithm, algo-project-x  |
| sm-algo-grace | 算法 | project-x | algorithm, algo-project-x  |
| sm-algo-henry | 算法 | project-x | algorithm, algo-project-x  |
| sm-algo-ivy   | 算法 | project-y | algorithm, algo-project-y  |
| sm-algo-jack  | 算法 | project-y | algorithm, algo-project-y  |

---

## 4. IAM Roles 设计

### 4.1 Role 类型

| Role 类型                | 用途                   | 信任实体                |
| ------------------------ | ---------------------- | ----------------------- |
| SageMaker Execution Role | Notebook 执行时的权限  | sagemaker.amazonaws.com |
| Service-Linked Role      | SageMaker 服务内部使用 | 自动创建                |

### 4.2 Execution Role 设计

**每个项目一个 Execution Role**（而非每用户一个）：

```
IAM Roles
├── SageMaker-RiskControl-ProjectA-ExecutionRole
│   └── 可访问: s3://company-sagemaker-rc-project-a/*
├── SageMaker-RiskControl-ProjectB-ExecutionRole
│   └── 可访问: s3://company-sagemaker-rc-project-b/*
├── SageMaker-Algorithm-ProjectX-ExecutionRole
│   └── 可访问: s3://company-sagemaker-algo-project-x/*
└── SageMaker-Algorithm-ProjectY-ExecutionRole
    └── 可访问: s3://company-sagemaker-algo-project-y/*
```

### 4.3 Execution Role 权限范围

| 权限类型   | 范围          | 说明          |
| ---------- | ------------- | ------------- |
| S3         | 仅项目 Bucket | 读写项目数据  |
| SageMaker  | 仅项目 Space  | 运行 Notebook |
| CloudWatch | 项目日志组    | 日志写入      |
| ECR        | 共享仓库      | 拉取容器镜像  |

### 4.4 Trust Policy（信任策略）

```
所有 Execution Role 的 Trust Policy:
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sagemaker.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

---

## 5. IAM Policies 设计

### 5.1 Policy 分层

```
IAM Policies
│
├── 基础层（所有开发者通用）
│   ├── SageMaker-Studio-Base-Access
│   └── SageMaker-Studio-CreatePresignedUrl
│
├── 团队层（团队级资源访问）
│   ├── SageMaker-RiskControl-Team-Access
│   └── SageMaker-Algorithm-Team-Access
│
├── 项目层（项目级资源访问）
│   ├── SageMaker-RiskControl-ProjectA-Access
│   ├── SageMaker-RiskControl-ProjectB-Access
│   ├── SageMaker-Algorithm-ProjectX-Access
│   └── SageMaker-Algorithm-ProjectY-Access
│
└── 角色层（Execution Role 权限）
    ├── SageMaker-RiskControl-ProjectA-ExecutionPolicy
    └── ...
```

### 5.2 基础策略设计

**SageMaker-Studio-Base-Access** - 所有用户的基础权限：

```
允许操作:
- sagemaker:DescribeDomain
- sagemaker:DescribeUserProfile
- sagemaker:CreatePresignedDomainUrl
- sagemaker:ListSpaces
- sagemaker:DescribeSpace

条件:
- 仅限指定 Domain
```

### 5.3 团队策略设计

**SageMaker-{Team}-Team-Access** - 团队级权限：

```
允许操作:
- sagemaker:DescribeSpace
- sagemaker:ListApps
- s3:ListBucket (团队前缀)

条件:
- Resource Tag: team = {team-name}
```

### 5.4 项目策略设计

**SageMaker-{Team}-{Project}-Access** - 项目级权限：

```
允许操作:
- sagemaker:CreateApp
- sagemaker:DeleteApp
- sagemaker:DescribeApp
- s3:GetObject
- s3:PutObject
- s3:DeleteObject

条件:
- Space: space-{team}-{project}
- S3 Bucket: company-sagemaker-{team}-{project}
```

---

## 6. 权限绑定关系

### 6.1 Group-Policy 绑定

| Group                    | 绑定 Policies                                                   |
| ------------------------ | --------------------------------------------------------------- |
| sagemaker-admins         | AmazonSageMakerFullAccess, AdminCustomPolicy                    |
| sagemaker-readonly       | SageMaker-ReadOnly-Access                                       |
| sagemaker-risk-control   | SageMaker-Studio-Base-Access, SageMaker-RiskControl-Team-Access |
| sagemaker-algorithm      | SageMaker-Studio-Base-Access, SageMaker-Algorithm-Team-Access   |
| sagemaker-rc-project-a   | SageMaker-RiskControl-ProjectA-Access                           |
| sagemaker-rc-project-b   | SageMaker-RiskControl-ProjectB-Access                           |
| sagemaker-algo-project-x | SageMaker-Algorithm-ProjectX-Access                             |
| sagemaker-algo-project-y | SageMaker-Algorithm-ProjectY-Access                             |

### 6.2 User-Group 绑定示例

```
sm-rc-alice:
  Groups:
    - sagemaker-risk-control    → Base + Team Access
    - sagemaker-rc-project-a    → Project A Access

  最终权限 = Base + Team + Project A
```

### 6.3 Execution Role 绑定

| Role                                         | User Profile                           | Space                |
| -------------------------------------------- | -------------------------------------- | -------------------- |
| SageMaker-RiskControl-ProjectA-ExecutionRole | profile-rc-alice, profile-rc-bob       | space-rc-project-a   |
| SageMaker-Algorithm-ProjectX-ExecutionRole   | profile-algo-frank, profile-algo-grace | space-algo-project-x |

---

## 7. 待完善内容

- [ ] 完整的 Policy JSON 模板
- [ ] iam:PassRole 权限配置
- [ ] Boundary Policy 设计
- [ ] 权限审计配置

---

## 8. 检查清单

### 创建前检查

- [ ] 确认命名规范
- [ ] 确认团队和项目清单
- [ ] 确认人员名单

### 创建后验证

- [ ] 用户可以登录 Console
- [ ] 用户可以访问 SageMaker Studio
- [ ] 用户只能看到自己项目的 Space
- [ ] 用户只能访问自己项目的 S3 数据
