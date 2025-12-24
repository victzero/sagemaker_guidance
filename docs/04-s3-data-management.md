# 04 - S3 数据管理

> 本文档描述 S3 Bucket 结构、权限策略和数据生命周期管理

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符 | 说明 | 示例值 |
|--------|------|--------|
| `{company}` | 公司/组织名称前缀 | `acme` |
| `{account-id}` | AWS 账号 ID | `123456789012` |
| `{team}` | 团队缩写 | `rc`、`algo` |
| `{project}` | 项目名称 | `project-a`、`project-x` |
| `{user}` | 用户名 | `alice`、`frank` |
| `{cost-center}` | 成本中心代码 | `ML-001` |

---

## 1. Bucket 规划

### 1.1 Bucket 策略

**方案选择**：每项目独立 Bucket

| 方案 | 优点 | 缺点 | 选择 |
|------|------|------|------|
| 单一 Bucket + Prefix | 管理简单 | 权限控制复杂 | ❌ |
| **每项目独立 Bucket** | 隔离清晰、权限简单 | Bucket 数量多 | ✅ |
| 每团队独立 Bucket | 折中 | 项目间隔离不足 | ❌ |

### 1.2 Bucket 清单

| Bucket 名称 | 团队 | 项目 | 用途 |
|-------------|------|------|------|
| `{company}-sm-rc-project-a` | 风控 | 项目A | 项目A 数据 |
| `{company}-sm-rc-project-b` | 风控 | 项目B | 项目B 数据 |
| `{company}-sm-algo-project-x` | 算法 | 项目X | 项目X 数据 |
| `{company}-sm-algo-project-y` | 算法 | 项目Y | 项目Y 数据 |
| `{company}-sm-shared-assets` | 共享 | - | 共享模型、脚本 |

### 1.3 命名规范

```
{company}-sm-{team}-{project}

示例:
- {company}-sm-rc-project-a
- {company}-sm-algo-project-x
```

---

## 2. Bucket 内部结构

### 2.1 标准目录结构

每个项目 Bucket 采用统一的目录结构：

```
{company}-sm-{team}-{project}/
│
├── raw/                    # 原始数据
│   ├── uploads/            # 上传的原始文件
│   └── external/           # 外部导入数据
│
├── processed/              # 处理后数据
│   ├── cleaned/            # 清洗后数据
│   └── transformed/        # 转换后数据
│
├── features/               # 特征数据
│   └── v{version}/         # 版本化特征
│
├── models/                 # 模型文件
│   ├── training/           # 训练中间文件
│   ├── artifacts/          # 模型产物
│   └── registry/           # 模型注册
│
├── notebooks/              # Notebook 备份
│   └── archived/           # 归档的 Notebook
│
├── outputs/                # 输出结果
│   ├── reports/            # 分析报告
│   └── predictions/        # 预测结果
│
└── temp/                   # 临时文件
    └── {user}/             # 按用户隔离
```

### 2.2 共享 Bucket 结构

```
{company}-sm-shared-assets/
│
├── scripts/                # 共享脚本
│   ├── preprocessing/      # 预处理脚本
│   └── utils/              # 工具脚本
│
├── containers/             # 容器配置
│   └── dockerfiles/        # Dockerfile
│
├── datasets/               # 共享数据集
│   └── reference/          # 参考数据
│
└── documentation/          # 文档
```

---

## 3. Bucket 配置

### 3.1 基础配置

| 配置项 | 值 | 说明 |
|--------|-----|------|
| Region | ap-southeast-1 | 与 VPC 同 Region |
| Versioning | Enabled | 版本控制 |
| Encryption | SSE-S3 | 默认加密 |
| Public Access | Block All | 禁止公开访问 |
| Object Lock | Disabled | 按需启用 |

### 3.2 标签规范

每个 Bucket 必须包含以下标签：

| Tag Key | Tag Value | 示例 |
|---------|-----------|------|
| Team | {team} | risk-control |
| Project | {project} | project-a |
| Environment | production | production |
| CostCenter | {cost-center} | ML-001 |
| ManagedBy | sagemaker-platform | sagemaker-platform |

---

## 4. 权限策略设计

### 4.1 Bucket Policy 设计原则

1. **默认拒绝**：只允许明确授权的访问
2. **最小权限**：只授予必要操作
3. **基于角色**：通过 Execution Role 访问

### 4.2 项目 Bucket Policy 模板

```
Policy 要点:
1. 允许指定 Execution Role 访问
2. 允许项目成员通过 Console 查看
3. 拒绝其他所有访问
4. 条件限制 VPC 内访问
```

**允许的操作**:
- s3:GetObject
- s3:PutObject
- s3:DeleteObject
- s3:ListBucket
- s3:GetBucketLocation

**主体**:
- `arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole`
- `arn:aws:iam::{account-id}:user/sm-{team}-*`（项目成员）

### 4.3 共享 Bucket Policy

```
Policy 要点:
1. 只读访问（除管理员外）
2. 允许所有 SageMaker Execution Role 读取
3. 管理员可写入
```

**允许的操作（普通用户）**:
- s3:GetObject
- s3:ListBucket

---

## 5. 生命周期规则

### 5.1 自动清理规则

| 路径 | 规则 | 天数 | 说明 |
|------|------|------|------|
| temp/* | Delete | 7 | 临时文件自动清理 |
| models/training/* | Transition to IA | 30 | 训练文件降级存储 |
| notebooks/archived/* | Transition to IA | 60 | 归档 Notebook |
| outputs/predictions/* | Delete | 90 | 旧预测结果清理 |

### 5.2 版本管理规则

| 规则 | 设置 | 说明 |
|------|------|------|
| 非当前版本过期 | 90 天 | 保留最近 90 天版本 |
| 删除标记清理 | 1 天 | 清理空删除标记 |
| 不完整上传清理 | 7 天 | 清理失败的多段上传 |

---

## 6. 访问路径

### 6.1 Notebook 内访问

```
Notebook → Execution Role → S3 Bucket

权限检查:
1. Execution Role 是否有 S3 权限
2. Bucket Policy 是否允许该 Role
3. VPC Endpoint 是否配置正确
```

### 6.2 Console 访问

```
IAM User → Console → S3 Bucket

权限检查:
1. IAM User 是否有 S3 权限
2. Bucket Policy 是否允许该 User
```

---

## 7. 数据管理最佳实践

### 7.1 数据组织

| 实践 | 说明 |
|------|------|
| 版本化目录 | features/v1/, features/v2/ |
| 日期分区 | raw/uploads/2024/01/01/ |
| 元数据文件 | 每个目录包含 README.md |

### 7.2 数据安全

| 实践 | 说明 |
|------|------|
| 禁止公开 | Block Public Access |
| 加密存储 | SSE-S3 或 SSE-KMS |
| 访问日志 | 启用 Server Access Logging |
| 跨账号限制 | Bucket Policy 限制 Principal |

### 7.3 成本控制

| 实践 | 说明 |
|------|------|
| 生命周期规则 | 自动清理临时文件 |
| 智能分层 | Intelligent-Tiering |
| 存储类别 | 冷数据用 S3-IA 或 Glacier |

---

## 8. 权限绑定关系

### 8.1 Execution Role → Bucket

| Execution Role | 可访问 Bucket |
|----------------|---------------|
| SageMaker-RiskControl-ProjectA-ExecutionRole | {company}-sm-rc-project-a, {company}-sm-shared-assets (只读) |
| SageMaker-RiskControl-ProjectB-ExecutionRole | {company}-sm-rc-project-b, {company}-sm-shared-assets (只读) |
| SageMaker-Algorithm-ProjectX-ExecutionRole | {company}-sm-algo-project-x, {company}-sm-shared-assets (只读) |
| SageMaker-Algorithm-ProjectY-ExecutionRole | {company}-sm-algo-project-y, {company}-sm-shared-assets (只读) |

### 8.2 IAM User → Bucket (Console 访问)

| User Group | 可访问 Bucket |
|------------|---------------|
| sagemaker-rc-project-a | {company}-sm-rc-project-a |
| sagemaker-rc-project-b | {company}-sm-rc-project-b |
| sagemaker-algo-project-x | {company}-sm-algo-project-x |
| sagemaker-algo-project-y | {company}-sm-algo-project-y |

---

## 9. 待完善内容

- [ ] 完整的 Bucket Policy JSON
- [ ] 生命周期规则 JSON
- [ ] KMS 加密配置（如需要）
- [ ] 跨 Region 复制（如需要）

---

## 10. 检查清单

### 创建前
- [ ] 确认公司名称前缀
- [ ] 确认项目清单
- [ ] 确认 Region

### 创建时
- [ ] 启用版本控制
- [ ] 启用默认加密
- [ ] 阻止公开访问
- [ ] 添加标签

### 创建后
- [ ] 配置 Bucket Policy
- [ ] 配置生命周期规则
- [ ] 验证 Execution Role 访问
- [ ] 验证 IAM User 访问

