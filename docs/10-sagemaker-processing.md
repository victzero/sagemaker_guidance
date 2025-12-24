# 10 - SageMaker Processing

> 本文档描述 SageMaker Processing 的设计与配置

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符         | 说明              | 示例值                   |
| -------------- | ----------------- | ------------------------ |
| `{company}`    | 公司/组织名称前缀 | `acme`                   |
| `{account-id}` | AWS 账号 ID       | `123456789012`           |
| `{region}`     | AWS 区域          | `ap-southeast-1`         |
| `{team}`       | 团队缩写          | `rc`、`algo`             |
| `{project}`    | 项目名称          | `project-a`、`project-x` |

---

## 1. Processing 概述

### 1.1 什么是 SageMaker Processing

SageMaker Processing 提供托管的数据处理基础设施：

- **数据预处理**：清洗、转换、特征工程
- **后处理**：模型评估、结果分析
- **批量推理**：大规模离线预测

### 1.2 与 Studio Notebook 的关系

| 场景             | 推荐工具              | 说明                     |
| ---------------- | --------------------- | ------------------------ |
| 交互式探索       | Studio Notebook       | 快速迭代、可视化         |
| 生产级数据处理   | **Processing Job**    | 可复现、可调度、大规模   |
| 特征工程 Pipeline | Processing + Step Functions | 编排多步骤处理   |

### 1.3 Processing 类型

| 类型                | 说明                    | 适用场景           |
| ------------------- | ----------------------- | ------------------ |
| **SKLearn**         | scikit-learn 环境       | 通用数据处理       |
| **Spark**           | Apache Spark 集群       | 大规模数据处理     |
| **PyTorch/TF**      | 深度学习框架            | 特征嵌入、向量化   |
| **Custom Container** | 自定义镜像             | 特殊依赖           |

---

## 2. 权限设计

### 2.1 Processing Job 权限模型

```
用户 (IAM User)
    │
    │ 提交 Processing Job
    ▼
Processing Job
    │
    │ 使用 Execution Role
    ▼
Execution Role
    ├── 读取 S3 输入数据
    ├── 写入 S3 输出数据
    ├── 拉取 ECR 镜像
    └── 写入 CloudWatch Logs
```

### 2.2 Execution Role 权限

Processing Job 复用 Studio 的 Execution Role（项目级），需追加：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ProcessingJobPermissions",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateProcessingJob",
        "sagemaker:DescribeProcessingJob",
        "sagemaker:StopProcessingJob",
        "sagemaker:ListProcessingJobs"
      ],
      "Resource": "arn:aws:sagemaker:{region}:{account-id}:processing-job/*"
    },
    {
      "Sid": "ProcessingContainerAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2.3 用户提交 Job 的权限

IAM User 需要以下权限才能提交 Processing Job：

```json
{
  "Sid": "AllowSubmitProcessingJob",
  "Effect": "Allow",
  "Action": [
    "sagemaker:CreateProcessingJob",
    "sagemaker:DescribeProcessingJob",
    "sagemaker:ListProcessingJobs"
  ],
  "Resource": "arn:aws:sagemaker:{region}:{account-id}:processing-job/{team}-{project}-*",
  "Condition": {
    "StringEquals": {
      "sagemaker:RoleArn": "arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole"
    }
  }
}
```

---

## 3. 数据流设计

### 3.1 输入输出路径规范

```
S3 输入:
s3://{company}-sm-{team}-{project}/
├── raw/                    # 原始数据
│   └── uploads/
└── processed/              # 上一步输出

S3 输出:
s3://{company}-sm-{team}-{project}/
├── processed/              # 处理后数据
│   └── {job-name}/
└── features/               # 特征数据
    └── v{version}/
```

### 3.2 Job 命名规范

```
{team}-{project}-{job-type}-{timestamp}

示例:
- rc-project-a-preprocess-20240101-120000
- algo-project-x-feature-eng-20240101-130000
```

---

## 4. Processing Job 配置

### 4.1 SKLearnProcessor 示例

```python
from sagemaker.sklearn.processing import SKLearnProcessor
from sagemaker.processing import ProcessingInput, ProcessingOutput

sklearn_processor = SKLearnProcessor(
    framework_version='1.2-1',
    role='arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole',
    instance_type='ml.m5.xlarge',
    instance_count=1,
    base_job_name='{team}-{project}-preprocess',
    sagemaker_session=sagemaker_session,
    tags=[
        {'Key': 'Team', 'Value': '{team}'},
        {'Key': 'Project', 'Value': '{project}'}
    ]
)

sklearn_processor.run(
    code='preprocessing.py',
    inputs=[
        ProcessingInput(
            source='s3://{company}-sm-{team}-{project}/raw/',
            destination='/opt/ml/processing/input'
        )
    ],
    outputs=[
        ProcessingOutput(
            source='/opt/ml/processing/output',
            destination='s3://{company}-sm-{team}-{project}/processed/'
        )
    ]
)
```

### 4.2 实例类型建议

| 数据规模      | 推荐实例          | 说明               |
| ------------- | ----------------- | ------------------ |
| < 10 GB       | ml.m5.xlarge      | 4 vCPU, 16 GB      |
| 10-100 GB     | ml.m5.4xlarge     | 16 vCPU, 64 GB     |
| 100 GB - 1 TB | ml.m5.12xlarge    | 48 vCPU, 192 GB    |
| > 1 TB        | Spark Processing  | 分布式处理         |

---

## 5. 成本控制

### 5.1 成本优化策略

| 策略               | 说明                         |
| ------------------ | ---------------------------- |
| **Spot 实例**      | 可节省 60-90%，但可能被中断  |
| **合适的实例大小** | 避免过度配置                 |
| **数据分区处理**   | 分批处理减少内存需求         |
| **Job 超时设置**   | 避免失控任务持续计费         |

### 5.2 Spot 实例配置

```python
sklearn_processor = SKLearnProcessor(
    # ... 其他配置 ...
    max_runtime_in_seconds=3600,  # 1 小时超时
)

# 启用 Spot（通过 Estimator 或 boto3）
```

---

## 6. 监控与日志

### 6.1 CloudWatch Logs

Processing Job 日志自动写入：

```
/aws/sagemaker/ProcessingJobs/{job-name}
```

### 6.2 监控指标

| 指标                | 说明           | 告警建议         |
| ------------------- | -------------- | ---------------- |
| CPUUtilization      | CPU 使用率     | > 90% 持续 10 分钟 |
| MemoryUtilization   | 内存使用率     | > 85%            |
| DiskUtilization     | 磁盘使用率     | > 80%            |

---

## 7. 与现有架构集成

### 7.1 权限复用

Processing Job 复用 Studio 的：
- **Execution Role**：同一项目共享
- **S3 Bucket**：同一项目数据
- **VPC 配置**：同一网络环境

### 7.2 VPC 配置

```python
sklearn_processor = SKLearnProcessor(
    # ... 其他配置 ...
    network_config=NetworkConfig(
        enable_network_isolation=False,
        security_group_ids=['sg-sagemaker-studio'],
        subnets=['{subnet-a}', '{subnet-b}']
    )
)
```

---

## 8. CLI 命令

### 8.1 查看 Processing Jobs

```bash
# 列出 Processing Jobs
aws sagemaker list-processing-jobs \
  --sort-by CreationTime \
  --sort-order Descending \
  --max-results 20

# 查看 Job 详情
aws sagemaker describe-processing-job \
  --processing-job-name {job-name}
```

### 8.2 停止 Processing Job

```bash
aws sagemaker stop-processing-job \
  --processing-job-name {job-name}
```

---

## 9. 待完善内容

- [ ] Spark Processing 配置示例
- [ ] 自定义容器配置
- [ ] Step Functions 编排示例
- [ ] 完整的 IAM Policy JSON

---

## 10. 检查清单

### 配置前

- [ ] Execution Role 已有 Processing 权限
- [ ] S3 输入/输出路径已规划
- [ ] VPC 配置确认（如需 VPC 内运行）

### 提交 Job

- [ ] 使用正确的命名规范
- [ ] 配置合适的实例类型
- [ ] 设置超时时间
- [ ] 添加标签

### 运行后

- [ ] 检查 CloudWatch Logs
- [ ] 验证输出数据
- [ ] 清理临时文件

