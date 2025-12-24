# 09 - 附录与参考

> 本文档包含术语表、FAQ 和参考链接

---

## 1. 术语表

| 术语 | 说明 |
|------|------|
| **Domain** | SageMaker Studio 的逻辑边界，包含用户和配置 |
| **User Profile** | Domain 中代表单个用户的配置实体 |
| **Space** | 用于协作的共享或私有工作空间 |
| **Execution Role** | Notebook 执行代码时使用的 IAM 角色 |
| **ENI** | Elastic Network Interface，弹性网络接口 |
| **VPC Endpoint** | VPC 内访问 AWS 服务的私有端点 |
| **Presigned URL** | 临时授权的访问 URL |

---

## 2. FAQ

### Q1: 为什么选择单一 Domain？
**A**: 单一 Domain 便于统一管理，通过 User Profile 和 Space 实现隔离。多 Domain 会增加管理复杂度且无法跨团队协作。

### Q2: 用户可以同时属于多个项目吗？
**A**: 可以，但需要：
- 加入多个项目的 IAM Group
- User Profile 的 Execution Role 需要调整
- 建议创建多个 User Profile

### Q3: 如何控制计算成本？
**A**: 
- 设置实例自动关闭（Idle Timeout）
- 限制可用实例类型
- 设置 Budget 告警

### Q4: Notebook 数据存在哪里？
**A**: 
- User Profile Home: EFS（个人配置）
- Space: EBS（共享工作文件）
- 项目数据: S3 Bucket

### Q5: 如何备份 Notebook？
**A**: 
- 推荐将 Notebook 保存到 S3
- 或使用 Git 集成
- Space EBS 支持快照

---

## 3. 资源配额

### 3.1 SageMaker 默认配额

| 资源 | 默认配额 | 可调整 |
|------|----------|--------|
| Domains per Account | 5 | ✅ |
| User Profiles per Domain | 100 | ✅ |
| Spaces per Domain | 100 | ✅ |
| Apps per User Profile | 4 | ✅ |

### 3.2 建议申请配额

如果需要扩展，提前申请：
- [ ] User Profiles per Domain
- [ ] Spaces per Domain

---

## 4. 实例类型参考

### 4.1 开发/探索

| 实例类型 | vCPU | 内存 | 用途 |
|----------|------|------|------|
| ml.t3.medium | 2 | 4 GB | 基础开发 |
| ml.t3.large | 2 | 8 GB | 轻量分析 |
| ml.t3.xlarge | 4 | 16 GB | 数据处理 |

### 4.2 计算密集

| 实例类型 | vCPU | 内存 | 用途 |
|----------|------|------|------|
| ml.m5.xlarge | 4 | 16 GB | 中等计算 |
| ml.m5.2xlarge | 8 | 32 GB | 大数据处理 |
| ml.c5.2xlarge | 8 | 16 GB | CPU 密集 |

### 4.3 GPU

| 实例类型 | GPU | 内存 | 用途 |
|----------|-----|------|------|
| ml.g4dn.xlarge | 1x T4 | 16 GB | 轻量深度学习 |
| ml.p3.2xlarge | 1x V100 | 61 GB | 深度学习训练 |

---

## 5. 标签规范

### 5.1 必需标签

| Tag Key | 说明 | 示例值 |
|---------|------|--------|
| Team | 团队名称 | risk-control, algorithm |
| Project | 项目名称 | project-a, project-x |
| Environment | 环境 | production, staging |
| Owner | 所有者 | sm-rc-alice |
| CostCenter | 成本中心 | ML-001 |

### 5.2 可选标签

| Tag Key | 说明 | 示例值 |
|---------|------|--------|
| CreatedBy | 创建者 | admin@company.com |
| CreatedDate | 创建日期 | 2024-01-15 |
| Application | 应用名称 | fraud-detection |

---

## 6. 参考链接

### 6.1 AWS 官方文档

| 文档 | 链接 |
|------|------|
| SageMaker Domain | https://docs.aws.amazon.com/sagemaker/latest/dg/sm-domain.html |
| User Profiles | https://docs.aws.amazon.com/sagemaker/latest/dg/domain-user-profile.html |
| Spaces | https://docs.aws.amazon.com/sagemaker/latest/dg/domain-space.html |
| VPC Configuration | https://docs.aws.amazon.com/sagemaker/latest/dg/studio-notebooks-and-internet-access.html |
| IAM for SageMaker | https://docs.aws.amazon.com/sagemaker/latest/dg/security-iam.html |

### 6.2 最佳实践

| 文档 | 链接 |
|------|------|
| SageMaker Security | https://docs.aws.amazon.com/sagemaker/latest/dg/security.html |
| Multi-Account Strategy | https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html |

---

## 7. 变更记录

| 版本 | 日期 | 变更说明 | 作者 |
|------|------|----------|------|
| v0.1 | 2024-12-24 | 初始框架创建 | - |
| | | | |

---

## 8. 联系与支持

### 内部支持
- 平台团队: [待填写]
- Slack 频道: [待填写]

### AWS 支持
- AWS Support: https://console.aws.amazon.com/support/
- AWS re:Post: https://repost.aws/

