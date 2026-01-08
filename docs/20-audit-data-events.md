# SageMaker Studio 数据审计最佳实践指南 (S3 Data Events)

本文档旨在指导如何为 SageMaker Studio 环境配置**高精度、低噪音、低成本**的 S3 数据访问审计。

通过配置 CloudTrail S3 Data Events，您可以精确记录“谁（User Profile）在什么时候（Time）对哪个数据（S3 Object）做了什么操作（Read/Write）”。

## 核心目标

1.  **全量审计**: 确保所有 SageMaker Studio 用户对敏感数据的访问都被记录。
2.  **精准过滤**: 排除非 Studio 来源的干扰日志，仅关注 SageMaker Studio 的行为。
3.  **成本控制**: 仅对关键 Bucket 开启，利用高级筛选器减少日志量。

---

## 最佳实践方案

### 1. 架构设计

我们不监控所有 S3 桶，也不监控所有 IAM 角色的操作。我们只监控：

- **资源**: 存放敏感数据、生产数据的特定 S3 Bucket。
- **主体**: 仅限 SageMaker Studio 的 Execution Roles。

### 2. 黄金配置逻辑

一份标准的「Studio 数据审计黄金配置」应满足以下逻辑：

```sql
(
  -- 1. 限定资源类型为 S3 对象
  resources.type = "AWS::S3::Object"
)
AND
(
  -- 2. 限定目标 Bucket (只监控关键数据桶)
  resources.ARN startsWith "arn:aws:s3:::<your-sensitive-bucket>/"
)
AND
(
  -- 3. 限定操作者 (只监控 Studio Role)
  userIdentity.arn startsWith "arn:aws:sts::<account-id>:assumed-role/SageMaker-"
)
```

---

## 实施步骤 (AWS Console)

### Step 1: 准备工作

确认您的 Studio User Profile 使用的 IAM Role 命名具有统一前缀。

- 在本项目的 `sagemaker_guidance` 中，Role 默认命名格式为：`SageMaker-<Team>-<Project>-ExecutionRole`。
- 因此，我们统一筛选的前缀为: `arn:aws:iam::<your-account-id>:role/SageMaker-`。

### Step 2: 创建/配置 Trail

1.  登录 AWS Console，进入 **CloudTrail** 服务。
2.  点击左侧菜单 **Trails**。
3.  点击 **Create trail** (或选择现有的 Trail 点击 Edit)。
    - **Trail name**: 例如 `sagemaker-data-audit-trail`。
    - **Storage location**: 选择新建 S3 Bucket 或使用现有 Bucket 存放日志。
    - **CloudWatch Logs**: (可选，建议开启) 启用并指定 Log Group，便于后续搜索和告警。

### Step 3: 配置 Data Events (关键)

在 "Choose log events" 页面：

1.  **Event type**: 勾选 **Data events**。
2.  **Data event source**: 选择 **S3**。
3.  **Log selector template**: 不要选 "Log all S3 events"，请选择 **Custom** (自定义)。

### Step 4: 配置高级事件筛选器 (Advanced Event Selectors)

这是实现“黄金配置”的核心。请按以下截图逻辑配置筛选器：

#### 筛选器 1: 资源与操作

- **Field**: `resources.ARN`
- **Operator**: `StartsWith`
- **Value**: `arn:aws:s3:::<your-sensitive-bucket>/` (请替换为您真实的 Bucket 名称，注意结尾的 `/` 表示桶内所有对象)
  - _提示_: 可以添加多行 Value 来监控多个 Bucket。
- **Field**: `readOnly` (可选)
  - 如果您只关心“写/篡改”操作，设为 `false`。
  - 如果您关心“读/泄露”操作，设为 `true` 或不筛选(记录所有)。

#### 筛选器 2: 限定 Studio 角色 (降噪关键)

为了仅记录 Studio 的操作，排除其他后台服务或管理员的操作：

- **Field**: `userIdentity.arn`
- **Operator**: `StartsWith`
- **Value**: `arn:aws:sts::<your-account-id>:assumed-role/SageMaker-`
  - _解释_: Studio 用户操作时使用的是临时凭证 (Assumed Role)。此 ARN 格式通常为 `arn:aws:sts::<acct>:assumed-role/<RoleName>/<SessionName>`。
  - _注意_: 请将 `<your-account-id>` 替换为真实账号 ID，并确保您的 Role 名称以 `SageMaker-` 开头（参考项目中的 IAM 设计）。

#### 黄金配置逻辑 (等效表达式)

```sql
(
  -- 1. 限定资源类型为 S3 对象
  resources.type = "AWS::S3::Object"
)
AND
(
  -- 2. 限定目标 Bucket (只监控关键数据桶)
  resources.ARN startsWith "arn:aws:s3:::<your-sensitive-bucket>/"
)
AND
(
  -- 3. 限定操作者 (只监控 Studio Role)
  -- 注意这里使用的是 userIdentity.arn 匹配 assumed-role
  userIdentity.arn startsWith "arn:aws:sts::<your-account-id>:assumed-role/SageMaker-"
)
```

配置完成后，请按以下步骤验证：

1.  **模拟访问**:

    - 登录 SageMaker Studio。
    - 打开一个 Notebook，执行代码读取受监控 Bucket 中的文件：
      ```python
      import boto3
      import pandas as pd
      # 替换为您的受监控文件
      df = pd.read_csv('s3://<your-sensitive-bucket>/test.csv')
      ```

2.  **查看日志**:
    - 等待约 5-15 分钟 (CloudTrail 投递延迟)。
    - 进入 CloudTrail 控制台 -> **Event history** (注意: Data Events 默认不在 Event history 显示，需去 **CloudWatch Logs** 或 **S3** 查看)。
    - **推荐方式**: 去 CloudWatch Logs Insights 查询。

### CloudWatch Logs Insights 查询示例

```sql
fields @timestamp, eventName, userIdentity.principalId, resources.0.ARN, sourceIPAddress
| filter eventSource = "s3.amazonaws.com"
| filter resources.0.ARN like /<your-sensitive-bucket>/
| sort @timestamp desc
| limit 20
```

---

## 常见问题 (FAQ)

**Q1: 为什么要限定 `userIdentity.arn`？**
A: 如果不加这个限制，所有访问该 Bucket 的操作（包括 ETL 任务、管理员维护、其他应用读取）都会被记录。这不仅会产生海量无关日志，还会大幅增加 CloudTrail 费用。通过限定 `assumed-role/SageMaker-` 前缀，可以确保我们只审计 Studio 用户的交互式操作。

**Q2: 费用大概多少？**
A: CloudTrail Data Events 按处理的事件数量收费（约 $0.10 / 100,000 事件）。通过上述筛选器，您可以过滤掉 90% 以上的无关流量，从而显著降低成本。

**Q3: 能看到具体的 Python 代码吗？**
A: 不能。CloudTrail 记录的是 **API 调用**。您会看到“用户 A 读取了文件 B”，但无法看到用户是用 `pandas.read_csv` 还是 `boto3.get_object` 读取的。对于数据安全审计，知道“谁动了哪个文件”通常已经足够。
