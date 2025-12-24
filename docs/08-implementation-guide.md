# 08 - 实施步骤指南

> 本文档提供按顺序执行的实施清单

---

## 1. 实施概览

### 1.1 阶段划分

| 阶段    | 内容                | 预计时间 |
| ------- | ------------------- | -------- |
| Phase 1 | 准备工作 & 信息收集 | 1 天     |
| Phase 2 | IAM 资源创建        | 1 天     |
| Phase 3 | 网络配置            | 0.5 天   |
| Phase 4 | S3 配置             | 0.5 天   |
| Phase 5 | SageMaker 配置      | 1 天     |
| Phase 6 | 验证与交付          | 1 天     |

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

## 3. Phase 2: IAM 资源创建

### 3.1 创建 IAM Policies

| #   | Policy 名称                       | 用途       | 状态 |
| --- | --------------------------------- | ---------- | ---- |
| 1   | SageMaker-Studio-Base-Access      | 基础访问   | ☐    |
| 2   | SageMaker-RiskControl-Team-Access | 风控团队   | ☐    |
| 3   | SageMaker-Algorithm-Team-Access   | 算法团队   | ☐    |
| 4   | SageMaker-RC-ProjectA-Access      | 风控项目 A | ☐    |
| 5   | SageMaker-RC-ProjectB-Access      | 风控项目 B | ☐    |
| 6   | SageMaker-Algo-ProjectX-Access    | 算法项目 X | ☐    |
| 7   | SageMaker-Algo-ProjectY-Access    | 算法项目 Y | ☐    |

### 3.2 创建 IAM Roles (Execution Roles)

| #   | Role 名称                             | Trust                   | 状态 |
| --- | ------------------------------------- | ----------------------- | ---- |
| 1   | SageMaker-RC-ProjectA-ExecutionRole   | sagemaker.amazonaws.com | ☐    |
| 2   | SageMaker-RC-ProjectB-ExecutionRole   | sagemaker.amazonaws.com | ☐    |
| 3   | SageMaker-Algo-ProjectX-ExecutionRole | sagemaker.amazonaws.com | ☐    |
| 4   | SageMaker-Algo-ProjectY-ExecutionRole | sagemaker.amazonaws.com | ☐    |

### 3.3 创建 IAM Groups

| #   | Group 名称               | 绑定 Policies   | 状态 |
| --- | ------------------------ | --------------- | ---- |
| 1   | sagemaker-risk-control   | Base + Team     | ☐    |
| 2   | sagemaker-algorithm      | Base + Team     | ☐    |
| 3   | sagemaker-rc-project-a   | ProjectA-Access | ☐    |
| 4   | sagemaker-rc-project-b   | ProjectB-Access | ☐    |
| 5   | sagemaker-algo-project-x | ProjectX-Access | ☐    |
| 6   | sagemaker-algo-project-y | ProjectY-Access | ☐    |

### 3.4 创建 IAM Users

| #   | User 名称   | Groups                     | MFA | 状态 |
| --- | ----------- | -------------------------- | --- | ---- |
| 1   | sm-rc-alice | risk-control, rc-project-a | ☐   | ☐    |
| 2   | sm-rc-bob   | risk-control, rc-project-a | ☐   | ☐    |
| ... | ...         | ...                        | ☐   | ☐    |

---

## 4. Phase 3: 网络配置

### 4.1 创建安全组

| #   | SG 名称             | 用途       | 状态 |
| --- | ------------------- | ---------- | ---- |
| 1   | sg-sagemaker-studio | Studio ENI | ☐    |
| 2   | sg-vpc-endpoints    | Endpoints  | ☐    |

### 4.2 创建 VPC Endpoints

| #   | Endpoint          | 类型      | Subnet | 状态 |
| --- | ----------------- | --------- | ------ | ---- |
| 1   | sagemaker.api     | Interface | a, b   | ☐    |
| 2   | sagemaker.runtime | Interface | a, b   | ☐    |
| 3   | sagemaker.studio  | Interface | a, b   | ☐    |
| 4   | sts               | Interface | a, b   | ☐    |
| 5   | s3                | Gateway   | -      | ☐    |
| 6   | logs              | Interface | a, b   | ☐    |

### 4.3 验证网络

- [ ] 安全组规则正确
- [ ] Endpoint DNS 解析正常
- [ ] 路由表配置正确

### 4.4 验证 VPCOnly 依赖/出网策略

- [ ] 策略 A/B/C 已选定并完成配置（NAT/代理/无 NAT + 内部制品库）
- [ ] Notebook 内依赖安装与导入验证通过
- [ ] 出网边界验证通过（非白名单/公网访问按策略应失败）
- [ ] 失败可定位（DNS/路由/SG/NACL/Endpoint/代理）

---

## 5. Phase 4: S3 配置

### 5.1 创建 S3 Buckets

| #   | Bucket 名称                 | 加密   | 版本控制 | 状态 |
| --- | --------------------------- | ------ | -------- | ---- |
| 1   | {company}-sm-rc-project-a   | SSE-S3 | ✅       | ☐    |
| 2   | {company}-sm-rc-project-b   | SSE-S3 | ✅       | ☐    |
| 3   | {company}-sm-algo-project-x | SSE-S3 | ✅       | ☐    |
| 4   | {company}-sm-algo-project-y | SSE-S3 | ✅       | ☐    |
| 5   | {company}-sm-shared-assets  | SSE-S3 | ✅       | ☐    |

### 5.2 配置 Bucket Policies

| #   | Bucket         | Policy 配置                      | 状态 |
| --- | -------------- | -------------------------------- | ---- |
| 1   | rc-project-a   | 允许 RC-ProjectA-ExecutionRole   | ☐    |
| 2   | rc-project-b   | 允许 RC-ProjectB-ExecutionRole   | ☐    |
| 3   | algo-project-x | 允许 Algo-ProjectX-ExecutionRole | ☐    |
| 4   | algo-project-y | 允许 Algo-ProjectY-ExecutionRole | ☐    |
| 5   | shared-assets  | 允许所有 Execution Roles 只读    | ☐    |

### 5.3 配置生命周期规则

- [ ] temp/\* 7 天删除
- [ ] 非当前版本 90 天过期

---

## 6. Phase 5: SageMaker 配置

### 6.1 创建 Domain

| 配置项          | 值                  | 状态 |
| --------------- | ------------------- | ---- |
| Domain Name     | ml-platform-domain  | ☐    |
| Auth Mode       | IAM                 | ☐    |
| Network Mode    | VPCOnly             | ☐    |
| VPC             | vpc-xxx             | ☐    |
| Subnets         | subnet-a, subnet-b  | ☐    |
| Security Groups | sg-sagemaker-studio | ☐    |

### 6.2 创建 User Profiles

| #   | Profile 名称     | IAM User    | Execution Role | 状态 |
| --- | ---------------- | ----------- | -------------- | ---- |
| 1   | profile-rc-alice | sm-rc-alice | RC-ProjectA    | ☐    |
| 2   | profile-rc-bob   | sm-rc-bob   | RC-ProjectA    | ☐    |
| ... | ...              | ...         | ...            | ☐    |

### 6.3 创建 Shared Spaces

| #   | Space 名称           | 成员                | 状态 |
| --- | -------------------- | ------------------- | ---- |
| 1   | space-rc-project-a   | alice, bob, carol   | ☐    |
| 2   | space-rc-project-b   | david, emma         | ☐    |
| 3   | space-algo-project-x | frank, grace, henry | ☐    |
| 4   | space-algo-project-y | ivy, jack           | ☐    |

---

## 7. Phase 6: 验证与交付

### 7.1 功能验证

| #   | 测试项                   | 预期结果 | 实际结果 | 状态 |
| --- | ------------------------ | -------- | -------- | ---- |
| 1   | IAM User 登录 Console    | 成功     |          | ☐    |
| 2   | 访问 SageMaker Studio    | 成功     |          | ☐    |
| 3   | 只能看到自己的 Profile   | 是       |          | ☐    |
| 4   | 只能访问所属项目的 Space | 是       |          | ☐    |
| 5   | Notebook 内访问 S3       | 成功     |          | ☐    |
| 6   | 只能访问项目 Bucket      | 是       |          | ☐    |
| 7   | 不能访问其他项目 Bucket  | 是       |          | ☐    |

### 7.2 安全验证

| #   | 测试项                        | 预期结果 | 状态 |
| --- | ----------------------------- | -------- | ---- |
| 1   | 跨项目 S3 访问                | 拒绝     | ☐    |
| 2   | 访问他人 User Profile         | 拒绝     | ☐    |
| 3   | 访问其他项目 Space            | 拒绝     | ☐    |
| 4   | 选择超出实例白名单/上限       | 拒绝     | ☐    |
| 5   | 违反出网策略（非白名单/公网） | 拒绝     | ☐    |

### 7.3 交付文档

- [ ] 用户登录指南
- [ ] Notebook 使用指南
- [ ] 数据访问指南
- [ ] 常见问题 FAQ

---

## 8. 回滚计划

如实施失败，按以下顺序回滚：

```
1. 删除 Spaces
2. 删除 User Profiles
3. 删除 Domain
4. 删除 S3 Buckets (如有数据需备份)
5. 删除 VPC Endpoints
6. 删除 Security Groups
7. 删除 IAM Users
8. 删除 IAM Groups
9. 删除 IAM Roles
10. 删除 IAM Policies
```

---

## 9. 联系人

| 角色       | 姓名 | 联系方式 |
| ---------- | ---- | -------- |
| 项目负责人 |      |          |
| 平台管理员 |      |          |
| AWS 支持   |      |          |
