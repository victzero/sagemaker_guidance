# 09 - 附录与参考

> 本文档包含术语表、FAQ 和参考链接

---

## 1. 术语表

### 1.1 SageMaker 基础概念

| 术语              | 说明                                                    |
| ----------------- | ------------------------------------------------------- |
| **Domain**        | SageMaker Studio 的逻辑边界，包含用户和配置             |
| **User Profile**  | Domain 中代表用户在特定项目中的配置实体                 |
| **Private Space** | 用户的私有工作空间，继承 User Profile 的 Execution Role |
| **Shared Space**  | 多用户共享的工作空间（本项目未使用）                    |
| **Presigned URL** | 临时授权的 Studio 访问 URL                              |

### 1.2 IAM 角色（4 角色设计）

| 术语                | 说明                                      |
| ------------------- | ----------------------------------------- |
| **Execution Role**  | Notebook/Studio 执行代码时使用的 IAM 角色 |
| **Training Role**   | Training Jobs 提交时使用的 IAM 角色       |
| **Processing Role** | Processing Jobs 提交时使用的 IAM 角色     |
| **Inference Role**  | Inference Endpoints 部署时使用的 IAM 角色 |

### 1.3 网络概念

| 术语               | 说明                            |
| ------------------ | ------------------------------- |
| **ENI**            | Elastic Network Interface       |
| **VPC Endpoint**   | VPC 内访问 AWS 服务的私有端点   |
| **Security Group** | 虚拟防火墙，控制网络流量        |
| **VPCOnly**        | SageMaker Domain 的网络隔离模式 |

---

## 2. FAQ

### Q1: 为什么选择单一 Domain？

**A**: 单一 Domain 便于统一管理，通过 User Profile 和 Private Space 实现隔离。多 Domain 会增加管理复杂度且无法跨团队协作。

### Q2: 用户可以同时属于多个项目吗？

**A**: 可以。采用**一对多映射**设计：

- 每个用户在每个参与的项目中有独立的 User Profile + Private Space
- 例如：Alice 参与 fraud-detection 和 anti-money-laundering 两个项目
  - `profile-rc-fraud-alice` + `space-rc-fraud-alice`（访问 fraud S3）
  - `profile-rc-aml-alice` + `space-rc-aml-alice`（访问 aml S3）
- 用户登录时选择对应项目的 Profile，进入对应的 Space

### Q3: 如何控制计算成本？

**A**:

- **内置 Idle Shutdown**：60 分钟无活动自动关闭 JupyterLab
- 限制可用实例类型（通过 IAM Policy）
- 设置 AWS Budget 告警

### Q4: Notebook 数据存在哪里？

**A**:

- **User Profile Home**: EFS（个人配置、临时文件）
- **Private Space**: EBS（工作文件）
- **项目数据**: S3 Bucket（持久存储）

### Q5: 如何备份 Notebook？

**A**:

- **推荐**：将 Notebook 保存到项目 S3 Bucket
- 或使用 Git 集成（CodeCommit）
- EFS Home 应视为临时存储，不保证长期持久化

### Q6: 什么是 4 角色设计？

**A**: 每个项目有 4 个专用 IAM 角色：

| 角色           | 用途                     | 权限范围      |
| -------------- | ------------------------ | ------------- |
| ExecutionRole  | Notebook/Studio 交互     | 项目 S3 读写  |
| TrainingRole   | 提交 Training Jobs       | 训练资源 + S3 |
| ProcessingRole | 提交 Processing Jobs     | 处理资源 + S3 |
| InferenceRole  | 部署 Inference Endpoints | 推理资源 + S3 |

### Q7: 为什么需要 MFA？

**A**: 所有 IAM User 必须启用 MFA：

- 通过 IAM Policy 中的 `aws:MultiFactorAuthPresent` 条件强制
- 未启用 MFA 的用户无法访问 SageMaker 资源
- 提高平台安全性

### Q8: Private Space 和 Shared Space 有什么区别？

**A**:

| 特性           | Private Space     | Shared Space        |
| -------------- | ----------------- | ------------------- |
| 所有者         | 单个用户          | 多用户共享          |
| Execution Role | 继承 User Profile | 继承 Domain Default |
| 项目 S3 访问   | ✅ 有权限         | ❌ 无权限           |
| 数据隔离       | ✅ 完全隔离       | ⚠️ 共享             |

本项目使用 Private Space 以实现项目级数据隔离。

---

## 3. 资源配额

### 3.1 SageMaker 默认配额

| 资源                     | 默认配额 | 可调整 |
| ------------------------ | -------- | ------ |
| Domains per Account      | 5        | ✅     |
| User Profiles per Domain | 100      | ✅     |
| Spaces per Domain        | 100      | ✅     |
| Apps per User Profile    | 4        | ✅     |

### 3.2 建议申请配额

如果需要扩展，提前申请：

- [ ] User Profiles per Domain
- [ ] Spaces per Domain

---

## 4. 实例类型参考

### 4.1 开发/探索

| 实例类型     | vCPU | 内存  | 用途     |
| ------------ | ---- | ----- | -------- |
| ml.t3.medium | 2    | 4 GB  | 基础开发 |
| ml.t3.large  | 2    | 8 GB  | 轻量分析 |
| ml.t3.xlarge | 4    | 16 GB | 数据处理 |

### 4.2 计算密集

| 实例类型      | vCPU | 内存  | 用途       |
| ------------- | ---- | ----- | ---------- |
| ml.m5.xlarge  | 4    | 16 GB | 中等计算   |
| ml.m5.2xlarge | 8    | 32 GB | 大数据处理 |
| ml.c5.2xlarge | 8    | 16 GB | CPU 密集   |

### 4.3 GPU

| 实例类型       | GPU     | 内存  | 用途         |
| -------------- | ------- | ----- | ------------ |
| ml.g4dn.xlarge | 1x T4   | 16 GB | 轻量深度学习 |
| ml.p3.2xlarge  | 1x V100 | 61 GB | 深度学习训练 |

---

## 5. 标签规范

### 5.1 必需标签

| Tag Key     | 说明     | 示例值                      | 适用资源                    |
| ----------- | -------- | --------------------------- | --------------------------- |
| Team        | 团队名称 | `risk-control`, `algorithm` | 所有资源                    |
| Project     | 项目名称 | `fraud-detection`           | 所有资源                    |
| Environment | 环境     | `production`, `staging`     | 所有资源                    |
| Owner       | 所有者   | `sm-rc-alice` 或 `alice`    | User Profile, Private Space |
| ManagedBy   | 管理标识 | `acme-sagemaker`            | 所有资源                    |

### 5.2 资源特定标签

| Tag Key   | 说明       | 示例值                  | 适用资源      |
| --------- | ---------- | ----------------------- | ------------- |
| SpaceType | Space 类型 | `private`               | Private Space |
| RoleType  | 角色类型   | `execution`, `training` | IAM Role      |

### 5.3 可选标签

| Tag Key     | 说明     | 示例值                  |
| ----------- | -------- | ----------------------- |
| CostCenter  | 成本中心 | `ML-001`                |
| CreatedBy   | 创建者   | `admin@company.com`     |
| CreatedDate | 创建日期 | `2024-01-15`            |
| Application | 应用名称 | `fraud-detection-model` |

---

## 6. 参考链接

### 6.1 AWS 官方文档

| 文档              | 链接                                                                                      |
| ----------------- | ----------------------------------------------------------------------------------------- |
| SageMaker Domain  | https://docs.aws.amazon.com/sagemaker/latest/dg/sm-domain.html                            |
| User Profiles     | https://docs.aws.amazon.com/sagemaker/latest/dg/domain-user-profile.html                  |
| Spaces            | https://docs.aws.amazon.com/sagemaker/latest/dg/domain-space.html                         |
| VPC Configuration | https://docs.aws.amazon.com/sagemaker/latest/dg/studio-notebooks-and-internet-access.html |
| IAM for SageMaker | https://docs.aws.amazon.com/sagemaker/latest/dg/security-iam.html                         |

### 6.2 最佳实践

| 文档                   | 链接                                                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------- |
| SageMaker Security     | https://docs.aws.amazon.com/sagemaker/latest/dg/security.html                                                       |
| Multi-Account Strategy | https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html |

---

## 7. 变更记录

| 版本 | 日期       | 变更说明                                     | 作者 |
| ---- | ---------- | -------------------------------------------- | ---- |
| v0.1 | 2024-12-24 | 初始框架创建                                 | -    |
| v1.0 | 2025-01-05 | 4 角色设计、Private Space、MFA、标签规范更新 | -    |

---

## 8. 联系与支持

### 内部支持

- 平台团队: [待填写]
- Slack 频道: [待填写]

### AWS 支持

- AWS Support: https://console.aws.amazon.com/support/
- AWS re:Post: https://repost.aws/
