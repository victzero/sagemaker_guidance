# 08 - 实施步骤指南

> 本文档提供按顺序执行的实施清单

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符         | 说明                    | 示例值                              |
| -------------- | ----------------------- | ----------------------------------- |
| `{company}`    | 公司/组织名称前缀       | `acme`                              |
| `{TAG_PREFIX}` | 资源标签前缀            | `acme-sagemaker`                    |
| `{account-id}` | AWS 账号 ID             | `123456789012`                      |
| `{region}`     | AWS 区域                | `ap-southeast-1`                    |
| `{team}`       | 团队缩写                | `rc`、`algo`                        |
| `{project}`    | 项目名称                | `fraud-detection`、`recommendation` |
| `{name}`       | 用户名                  | `alice`、`david`                    |
| `{vpc-id}`     | VPC ID（待确认）        | `vpc-0abc123def456`                 |
| `{subnet-ids}` | 子网 ID（待确认）       | `subnet-a, subnet-b [, subnet-c]`   |
| `d-xxxxxxxxx`  | Domain ID（创建后获取） | `d-abc123def456`                    |

---

## 1. 实施概览

### 1.1 阶段划分

| 阶段     | 内容                   | 预计时间 | 脚本目录                                                    |
| -------- | ---------------------- | -------- | ----------------------------------------------------------- |
| Phase 1  | 准备工作 & 信息收集    | 1 天     | -                                                           |
| Phase 2A | IAM 资源创建           | 1 天     | `scripts/01-iam/`                                           |
| Phase 2B | ECR 容器仓库（可选）   | 0.25 天  | `scripts/06-ecr/`                                           |
| Phase 2C | Model Registry（可选） | 0.25 天  | `scripts/07-model-registry/`                                |
| Phase 3  | 网络配置               | 0.5 天   | `scripts/02-vpc/`                                           |
| Phase 4  | S3 配置                | 0.5 天   | `scripts/03-s3/`                                            |
| Phase 5  | SageMaker 配置         | 1 天     | `scripts/04-sagemaker-domain/`, `scripts/05-user-profiles/` |
| Phase 6  | 验证与交付             | 1 天     | -                                                           |

### 1.2 前置条件

- [ ] AWS 账号访问权限（Admin 或等效）
- [ ] 现有 VPC 信息
- [ ] 团队和项目人员名单
- [ ] 网络规划确认

---

## 2. Phase 1: 准备工作

### 2.1 信息收集

| 信息项             | 值  | 状态 |
| ------------------ | --- | ---- |
| AWS Account ID     |     | ☐    |
| Region             |     | ☐    |
| VPC ID             |     | ☐    |
| Private Subnet IDs |     | ☐    |
| 公司名称前缀       |     | ☐    |

### 2.2 人员名单确认

| 团队 | 项目      | 成员 | IAM 用户名  | 状态 |
| ---- | --------- | ---- | ----------- | ---- |
| 风控 | project-a |      | sm-rc-xxx   | ☐    |
| 风控 | project-b |      | sm-rc-xxx   | ☐    |
| 算法 | project-x |      | sm-algo-xxx | ☐    |
| 算法 | project-y |      | sm-algo-xxx | ☐    |

### 2.3 命名规范确认

- [ ] Bucket 命名前缀
- [ ] IAM 命名规范
- [ ] Space 命名规范
- [ ] 标签规范

### 2.4 两个验收高风险决策（建议先定）

- [ ] **IAM Domain 下“只能打开自己的 Profile”**：确定强制点（Presigned URL / CreateApp）与验收用例（见 `02-iam-design.md`、`06-user-profile.md`）
- [ ] **VPCOnly 出网策略**：选择 A/B/C（允许出网 / 受控出网 / 禁止出网），并明确依赖获取方案（见 `03-vpc-network.md`）

---

## 3. Phase 2A: IAM 资源创建

> 📖 详细 Policy JSON 模板见 [02-IAM 设计](./02-iam-design.md)
>
> 💡 **推荐**：使用自动化脚本 `scripts/01-iam/setup-all.sh`

```bash
cd scripts/01-iam
./setup-all.sh    # 一键创建所有 IAM 资源
./verify.sh       # 验证配置
```

### 3.1 创建 IAM Policies（7 个基础策略 + 12 个/项目）

**基础策略（共 7 个）**：

| #   | Policy 名称                    | 用途                    | 状态 |
| --- | ------------------------------ | ----------------------- | ---- |
| 1   | SageMaker-Studio-Base-Access   | 基础访问                | ☐    |
| 2   | SageMaker-{Team}-Team-Access   | 团队访问（每团队 1 个） | ☐    |
| 3   | SageMaker-StudioAppPermissions | Studio App 权限         | ☐    |
| 4   | SageMaker-MLflowAppAccess      | MLflow 访问             | ☐    |
| 5   | SageMaker-Shared-DenyAdmin     | 禁止管理员操作          | ☐    |
| 6   | SageMaker-Shared-PassRole      | PassRole 权限           | ☐    |
| 7   | SageMaker-Shared-S3Access      | S3 共享桶访问           | ☐    |

**项目策略（每项目 12 个）**：

| #     | Policy 命名格式                                   | 用途                    |
| ----- | ------------------------------------------------- | ----------------------- |
| 1-3   | SageMaker-{Team}-{Project}-ExecutionRole-{1,2,3}  | Execution Role（拆分）  |
| 4-6   | SageMaker-{Team}-{Project}-TrainingRole-{1,2,3}   | Training Role（拆分）   |
| 7-9   | SageMaker-{Team}-{Project}-ProcessingRole-{1,2,3} | Processing Role（拆分） |
| 10-12 | SageMaker-{Team}-{Project}-InferenceRole-{1,2,3}  | Inference Role（拆分）  |

> 📌 策略拆分设计：每个角色拆分为 3 个策略，避免 6KB 限制。

### 3.2 创建 IAM Roles（4 角色设计）

> ⚠️ **重要**：Domain 默认角色是创建 Domain 的**必需前置条件**

**Domain 默认角色（必需）**：

| Role 名称                             | Trust                   | 说明        | 状态 |
| ------------------------------------- | ----------------------- | ----------- | ---- |
| SageMaker-Domain-DefaultExecutionRole | sagemaker.amazonaws.com | Domain 必需 | ☐    |

**项目 4 角色（每项目）**：

| #   | Role 命名格式                             | 用途               | Trust                   |
| --- | ----------------------------------------- | ------------------ | ----------------------- |
| 1   | SageMaker-{Team}-{Project}-ExecutionRole  | Notebook/Studio    | sagemaker.amazonaws.com |
| 2   | SageMaker-{Team}-{Project}-TrainingRole   | Training Jobs      | sagemaker.amazonaws.com |
| 3   | SageMaker-{Team}-{Project}-ProcessingRole | Processing Jobs    | sagemaker.amazonaws.com |
| 4   | SageMaker-{Team}-{Project}-InferenceRole  | Inference/Endpoint | sagemaker.amazonaws.com |

### 3.3 创建 IAM Groups

| #   | Group 命名格式             | 绑定 Policies                      | 状态 |
| --- | -------------------------- | ---------------------------------- | ---- |
| 1   | sagemaker-{team}           | Base + Team + DenyAdmin + PassRole | ☐    |
| 2   | sagemaker-{team}-{project} | Project-Access                     | ☐    |

### 3.4 创建 IAM Users

| #   | User 命名格式    | Groups                                       | MFA     | 状态 |
| --- | ---------------- | -------------------------------------------- | ------- | ---- |
| 1   | sm-{team}-{user} | sagemaker-{team}, sagemaker-{team}-{project} | 必需 ✅ | ☐    |

> 📌 MFA 强制要求：所有 IAM User 必须启用 MFA（策略中通过 `aws:MultiFactorAuthPresent` 条件强制）。

---

## 3A. Phase 2B: ECR 容器仓库（可选）

> 📖 详细说明见 [scripts/06-ecr/README.md](../scripts/06-ecr/README.md)

如果需要自定义 Docker 镜像：

```bash
cd scripts/06-ecr
./setup-all.sh
```

| 仓库类型 | 命名格式                                 | 用途     |
| -------- | ---------------------------------------- | -------- |
| 共享仓库 | `{company}-sagemaker-shared/base-{type}` | 基础镜像 |
| 项目仓库 | `{company}-sm-{team}-{project}/{type}`   | 项目镜像 |

---

## 3B. Phase 2C: Model Registry（可选）

> 📖 详细说明见 [scripts/07-model-registry/README.md](../scripts/07-model-registry/README.md)

如果需要模型版本管理：

```bash
cd scripts/07-model-registry
./setup-all.sh
```

| 资源                | 命名格式           | 用途         |
| ------------------- | ------------------ | ------------ |
| Model Package Group | `{team}-{project}` | 模型版本管理 |

---

## 4. Phase 3: 网络配置

> 📖 详细说明见 [03-VPC 网络](./03-vpc-network.md)
>
> 💡 **推荐**：使用自动化脚本 `scripts/02-vpc/setup-all.sh`

```bash
cd scripts/02-vpc
./setup-all.sh    # 一键创建安全组和 VPC Endpoints
./verify.sh       # 验证配置
```

### 4.1 创建安全组

| #   | SG 命名格式                  | 用途                | 状态 |
| --- | ---------------------------- | ------------------- | ---- |
| 1   | `{TAG_PREFIX}-studio`        | Studio ENI          | ☐    |
| 2   | `{TAG_PREFIX}-vpc-endpoints` | VPC Endpoints       | ☐    |
| 3   | `{TAG_PREFIX}-training`      | Training Jobs       | ☐    |
| 4   | `{TAG_PREFIX}-processing`    | Processing Jobs     | ☐    |
| 5   | `{TAG_PREFIX}-inference`     | Inference Endpoints | ☐    |

### 4.2 创建 VPC Endpoints

**必需 Endpoints（6 个）**：

| #   | Endpoint          | 类型      | Subnet    | 状态 |
| --- | ----------------- | --------- | --------- | ---- |
| 1   | sagemaker.api     | Interface | a, b [,c] | ☐    |
| 2   | sagemaker.runtime | Interface | a, b [,c] | ☐    |
| 3   | sagemaker.studio  | Interface | a, b [,c] | ☐    |
| 4   | sts               | Interface | a, b [,c] | ☐    |
| 5   | s3                | Gateway   | -         | ☐    |
| 6   | logs              | Interface | a, b [,c] | ☐    |

**可选 Endpoints**：

| #   | Endpoint          | 用途                | 状态 |
| --- | ----------------- | ------------------- | ---- |
| 7   | ecr.api + ecr.dkr | 自定义容器镜像      | ☐    |
| 8   | kms               | KMS 加密            | ☐    |
| 9   | ssm + ssmmessages | Systems Manager     | ☐    |
| 10  | bedrock-runtime   | SageMaker Canvas AI | ☐    |

### 4.3 验证网络

- [ ] 安全组规则正确（自引用 + VPC CIDR）
- [ ] Endpoint DNS 解析正常
- [ ] 路由表配置正确（2-3 个）
- [ ] Workload 安全组已创建（Training/Processing/Inference）

### 4.4 验证 VPCOnly 依赖/出网策略

- [ ] 策略 A/B/C 已选定并完成配置（NAT/代理/无 NAT + 内部制品库）
- [ ] Notebook 内依赖安装与导入验证通过
- [ ] 出网边界验证通过（非白名单/公网访问按策略应失败）
- [ ] 失败可定位（DNS/路由/SG/NACL/Endpoint/代理）

---

## 5. Phase 4: S3 配置

> 📖 详细说明见 [04-S3 数据管理](./04-s3-data-management.md)
>
> 💡 **推荐**：使用自动化脚本 `scripts/03-s3/setup-all.sh`

```bash
cd scripts/03-s3
./setup-all.sh    # 一键创建 Buckets 和配置
./verify.sh       # 验证配置
```

### 5.1 创建 S3 Buckets

| #   | Bucket 命名格式                 | 加密   | 版本控制 | 状态 |
| --- | ------------------------------- | ------ | -------- | ---- |
| 1   | `{company}-sm-{team}-{project}` | SSE-S3 | ✅       | ☐    |
| 2   | `{company}-sm-shared-assets`    | SSE-S3 | ✅       | ☐    |

**示例**（2 团队 × 2 项目 + 1 共享）：

- `acme-sm-rc-fraud-detection`
- `acme-sm-rc-anti-money-laundering`
- `acme-sm-algo-recommendation`
- `acme-sm-algo-forecasting`
- `acme-sm-shared-assets`

### 5.2 配置 Bucket Policies

| Bucket 类型 | 允许的角色                                             | 权限 |
| ----------- | ------------------------------------------------------ | ---- |
| 项目 Bucket | 项目 4 角色（Execution/Training/Processing/Inference） | 读写 |
| 项目 Bucket | 项目成员 IAM Users                                     | 读写 |
| 共享 Bucket | 所有 SageMaker Execution Roles                         | 只读 |
| 共享 Bucket | 所有 `sm-*` IAM Users                                  | 只读 |
| 共享 Bucket | `sm-admin-*` IAM Users                                 | 读写 |

### 5.3 配置生命周期规则

- [ ] `temp/*` 7 天删除
- [ ] `models/` 30 天转 IA，365 天转 Glacier
- [ ] `notebooks/` 90 天转 IA
- [ ] 非当前版本 90 天过期

---

## 6. Phase 5: SageMaker 配置

> 📖 CLI 命令详见：
>
> - Domain: [05-SageMaker Domain](./05-sagemaker-domain.md)
> - User Profile & Private Space: [06-User Profile](./06-user-profile.md)

### 6.1 创建 Domain

> 💡 **推荐**：使用自动化脚本 `scripts/04-sagemaker-domain/setup-all.sh`

```bash
cd scripts/04-sagemaker-domain
./check.sh          # 前置检查
./setup-all.sh      # 创建 Domain（含内置 Idle Shutdown）
./verify.sh         # 验证配置
```

| 配置项                     | 值                                      | 状态 |
| -------------------------- | --------------------------------------- | ---- |
| Domain Name                | `{company}-ml-platform`                 | ☐    |
| Auth Mode                  | IAM                                     | ☐    |
| Network Mode               | VPCOnly                                 | ☐    |
| VPC                        | `{vpc-id}`                              | ☐    |
| Subnets                    | `{subnet-ids}` (2-3 个)                 | ☐    |
| Security Groups            | `{TAG_PREFIX}-studio`                   | ☐    |
| **Default Execution Role** | `SageMaker-Domain-DefaultExecutionRole` | ☐    |
| **Idle Shutdown**          | ENABLED (60 分钟)                       | ☐    |
| Domain ID                  | d-xxxxxxxxx（记录）                     | ☐    |

> ⚠️ **重要**：`DefaultUserSettings` 和 `DefaultSpaceSettings` 都必须包含 `ExecutionRole`

### 6.2 配置 Idle Shutdown（成本控制）

> 📌 **推荐**：使用 SageMaker **内置 Idle Shutdown**（非自定义 Lifecycle Config）

- [ ] 启用内置 `AppLifecycleManagement.IdleSettings`
- [ ] 设置 `IdleTimeoutInMinutes: 60`
- [ ] 验证空闲 60 分钟后自动关闭

如果之前使用自定义 Lifecycle Config 导致启动失败，运行：

```bash
cd scripts/04-sagemaker-domain
./fix-lifecycle-config.sh    # 迁移到内置 Idle Shutdown
```

### 6.3 创建 User Profiles 和 Private Spaces

> 💡 **推荐**：使用自动化脚本 `scripts/05-user-profiles/setup-all.sh`

```bash
cd scripts/05-user-profiles
./setup-all.sh      # 创建所有 User Profiles + Private Spaces
./verify.sh         # 验证配置
```

**命名规范**：

| 资源类型      | 命名格式                          | 示例                     |
| ------------- | --------------------------------- | ------------------------ |
| User Profile  | `profile-{team}-{project}-{user}` | `profile-rc-fraud-alice` |
| Private Space | `space-{team}-{project}-{user}`   | `space-rc-fraud-alice`   |

脚本会自动：

- 读取 `.env.shared` 中的团队和用户配置
- 为每个用户在每个参与的项目中创建 User Profile
- 为每个 Profile 创建对应的 Private Space
- 绑定正确的项目 Execution Role
- 设置正确的 Tags（Team, Project, Owner, SpaceType）

> 📌 **一对多映射**：一个用户可参与多个项目，每个项目有独立的 Profile + Space。

---

## 7. Phase 6: 验证与交付

### 7.1 功能验证

| #   | 测试项                            | 预期结果 | 实际结果 | 状态 |
| --- | --------------------------------- | -------- | -------- | ---- |
| 1   | IAM User 登录 Console             | 成功     |          | ☐    |
| 2   | 访问 SageMaker Studio             | 成功     |          | ☐    |
| 3   | 只能看到自己的 Profile            | 是       |          | ☐    |
| 4   | 选择 Profile 后进入 Private Space | 是       |          | ☐    |
| 5   | Notebook 内访问项目 S3            | 成功     |          | ☐    |
| 6   | 只能访问项目 Bucket               | 是       |          | ☐    |
| 7   | 不能访问其他项目 Bucket           | 是       |          | ☐    |
| 8   | 空闲 60 分钟后自动关机            | 是       |          | ☐    |

### 7.2 安全验证

| #   | 测试项                            | 预期结果 | 状态 |
| --- | --------------------------------- | -------- | ---- |
| 1   | 跨项目 S3 访问                    | 拒绝     | ☐    |
| 2   | 访问他人 User Profile             | 拒绝     | ☐    |
| 3   | 访问他人 Private Space            | 拒绝     | ☐    |
| 4   | 同一用户不同项目 Profile 数据隔离 | 是       | ☐    |
| 5   | 选择超出实例白名单/上限           | 拒绝     | ☐    |
| 6   | 违反出网策略（非白名单/公网）     | 拒绝     | ☐    |
| 7   | 无 MFA 用户访问 SageMaker         | 拒绝     | ☐    |

### 7.3 4 角色设计验证

| #   | 测试项                             | 预期结果 | 状态 |
| --- | ---------------------------------- | -------- | ---- |
| 1   | ExecutionRole 访问项目 S3          | 成功     | ☐    |
| 2   | TrainingRole 提交 Training Job     | 成功     | ☐    |
| 3   | ProcessingRole 提交 Processing Job | 成功     | ☐    |
| 4   | InferenceRole 部署 Endpoint        | 成功     | ☐    |

### 7.4 交付文档

- [ ] 用户登录指南
- [ ] Notebook 使用指南
- [ ] 数据访问指南（项目 S3 桶）
- [ ] 多项目切换指南（一个用户多个 Profile）
- [ ] 常见问题 FAQ

---

## 8. 回滚计划

如实施失败，按以下顺序回滚：

```
1. 删除 Private Spaces (删除 Space 内的 Apps → 删除 Space)
2. 删除 User Profiles
3. 删除 Domain
4. 删除 Model Package Groups (07-model-registry)
5. 删除 ECR Repositories (06-ecr)
6. 删除 S3 Buckets (如有数据需备份)
7. 删除 VPC Endpoints
8. 删除 Security Groups (Studio + Workload)
9. 删除 IAM Users
10. 删除 IAM Groups
11. 删除 IAM Roles (4 角色 × 项目数 + Domain Default)
12. 删除 IAM Policies
```

**使用清理脚本**（按相反顺序执行）：

```bash
# ⚠️ 危险操作 - 每个脚本需要手动确认
cd scripts/05-user-profiles && ./cleanup.sh
cd scripts/04-sagemaker-domain && ./cleanup.sh
cd scripts/07-model-registry && ./cleanup.sh
cd scripts/06-ecr && ./cleanup.sh
cd scripts/03-s3 && ./cleanup.sh
cd scripts/02-vpc && ./cleanup.sh
cd scripts/01-iam && ./cleanup.sh
```

---

## 9. 联系人

| 角色       | 姓名 | 联系方式 |
| ---------- | ---- | -------- |
| 项目负责人 |      |          |
| 平台管理员 |      |          |
| AWS 支持   |      |          |
