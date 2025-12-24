# 12 - SageMaker Training

> 本文档描述 SageMaker Training 的设计与配置

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

## 1. Training 概述

### 1.1 什么是 SageMaker Training

SageMaker Training 提供托管的模型训练基础设施：

- **托管计算**：无需管理服务器
- **分布式训练**：支持多机多卡
- **内置算法**：XGBoost、线性学习器等
- **自定义脚本**：支持 PyTorch、TensorFlow 等
- **超参数调优**：自动化调参

### 1.2 与 Studio Notebook 的关系

| 场景               | 推荐工具            | 说明                     |
| ------------------ | ------------------- | ------------------------ |
| 模型原型开发       | Studio Notebook     | 快速迭代、调试           |
| 正式模型训练       | **Training Job**    | 可复现、可追溯           |
| 超参数搜索         | HPO Job             | 自动化调参               |
| Pipeline 集成      | Training Step       | ML Pipeline              |

### 1.3 训练模式

| 模式               | 说明                    | 适用场景             |
| ------------------ | ----------------------- | -------------------- |
| **单机单卡**       | 1 实例                  | 小数据集、快速验证   |
| **单机多卡**       | 1 实例多 GPU            | 中等规模             |
| **多机分布式**     | 多实例数据并行/模型并行 | 大规模训练           |

---

## 2. 权限设计

### 2.1 Training Job 权限模型

```
用户 (IAM User / Studio)
    │
    │ 提交 Training Job
    ▼
Training Job
    │
    │ 使用 Execution Role
    ▼
Execution Role
├── 读取 S3 训练数据
├── 写入 S3 模型产物
├── 拉取 ECR 镜像
├── 写入 CloudWatch Logs
└── 访问 KMS（如加密）
```

### 2.2 Execution Role 追加权限

在现有 Execution Role 基础上追加：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TrainingJobPermissions",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateTrainingJob",
        "sagemaker:DescribeTrainingJob",
        "sagemaker:StopTrainingJob",
        "sagemaker:ListTrainingJobs"
      ],
      "Resource": "arn:aws:sagemaker:{region}:{account-id}:training-job/*"
    },
    {
      "Sid": "TrainingModelArtifacts",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-{team}-{project}",
        "arn:aws:s3:::{company}-sm-{team}-{project}/*"
      ]
    },
    {
      "Sid": "TrainingContainerAccess",
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

### 2.3 用户提交 Job 权限

IAM User 需要以下权限：

```json
{
  "Sid": "AllowSubmitTrainingJob",
  "Effect": "Allow",
  "Action": [
    "sagemaker:CreateTrainingJob",
    "sagemaker:DescribeTrainingJob",
    "sagemaker:ListTrainingJobs",
    "sagemaker:StopTrainingJob"
  ],
  "Resource": "arn:aws:sagemaker:{region}:{account-id}:training-job/{team}-{project}-*",
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
├── features/               # 特征数据
│   └── v{version}/
└── processed/              # 处理后数据

S3 输出:
s3://{company}-sm-{team}-{project}/
└── models/
    ├── training/           # 训练中间产物
    │   └── {job-name}/
    └── artifacts/          # 最终模型
        └── {model-name}/
            └── v{version}/
```

### 3.2 Job 命名规范

```
{team}-{project}-{model-type}-{timestamp}

示例:
- rc-project-a-xgboost-20240101-120000
- algo-project-x-pytorch-cnn-20240101-130000
```

---

## 4. Training Job 配置

### 4.1 PyTorch Estimator 示例

```python
from sagemaker.pytorch import PyTorch

estimator = PyTorch(
    entry_point='train.py',
    source_dir='./src',
    role='arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole',
    instance_count=1,
    instance_type='ml.p3.2xlarge',
    framework_version='2.0.1',
    py_version='py310',
    base_job_name='{team}-{project}-pytorch',
    output_path='s3://{company}-sm-{team}-{project}/models/artifacts/',
    code_location='s3://{company}-sm-{team}-{project}/models/training/',
    hyperparameters={
        'epochs': 10,
        'batch-size': 32,
        'learning-rate': 0.001
    },
    tags=[
        {'Key': 'Team', 'Value': '{team}'},
        {'Key': 'Project', 'Value': '{project}'}
    ],
    # VPC 配置
    subnets=['{subnet-a}', '{subnet-b}'],
    security_group_ids=['sg-sagemaker-studio'],
    # Spot 实例（可选）
    use_spot_instances=True,
    max_wait=7200,
    max_run=3600
)

estimator.fit({
    'train': 's3://{company}-sm-{team}-{project}/features/v1/train/',
    'validation': 's3://{company}-sm-{team}-{project}/features/v1/validation/'
})
```

### 4.2 XGBoost 示例

```python
from sagemaker.xgboost import XGBoost

xgb_estimator = XGBoost(
    entry_point='train.py',
    role='arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole',
    instance_count=1,
    instance_type='ml.m5.xlarge',
    framework_version='1.7-1',
    base_job_name='{team}-{project}-xgboost',
    output_path='s3://{company}-sm-{team}-{project}/models/artifacts/',
    hyperparameters={
        'max_depth': 5,
        'eta': 0.2,
        'objective': 'binary:logistic',
        'num_round': 100
    }
)
```

### 4.3 实例类型建议

| 训练类型     | 推荐实例            | 说明                 |
| ------------ | ------------------- | -------------------- |
| 表格数据 ML  | ml.m5.xlarge        | CPU 足够             |
| 树模型       | ml.m5.4xlarge       | XGBoost/LightGBM     |
| 深度学习小型 | ml.g4dn.xlarge      | 单 GPU               |
| 深度学习中型 | ml.p3.2xlarge       | V100 GPU             |
| 深度学习大型 | ml.p3.8xlarge       | 4x V100              |
| 分布式训练   | ml.p3.16xlarge x N  | 8x V100 x N          |

---

## 5. 分布式训练

### 5.1 数据并行

```python
from sagemaker.pytorch import PyTorch

estimator = PyTorch(
    # ... 基础配置 ...
    instance_count=2,
    instance_type='ml.p3.16xlarge',
    distribution={
        'smdistributed': {
            'dataparallel': {
                'enabled': True
            }
        }
    }
)
```

### 5.2 模型并行

```python
distribution={
    'smdistributed': {
        'modelparallel': {
            'enabled': True,
            'parameters': {
                'partitions': 2,
                'microbatches': 4
            }
        }
    }
}
```

---

## 6. 超参数调优 (HPO)

### 6.1 HPO Job 配置

```python
from sagemaker.tuner import HyperparameterTuner, ContinuousParameter, IntegerParameter

hyperparameter_ranges = {
    'learning-rate': ContinuousParameter(0.001, 0.1, scaling_type='Logarithmic'),
    'batch-size': IntegerParameter(16, 128),
    'epochs': IntegerParameter(5, 20)
}

tuner = HyperparameterTuner(
    estimator=estimator,
    objective_metric_name='validation:accuracy',
    hyperparameter_ranges=hyperparameter_ranges,
    max_jobs=20,
    max_parallel_jobs=4,
    strategy='Bayesian',
    base_tuning_job_name='{team}-{project}-hpo'
)

tuner.fit({
    'train': 's3://{company}-sm-{team}-{project}/features/v1/train/',
    'validation': 's3://{company}-sm-{team}-{project}/features/v1/validation/'
})
```

---

## 7. 成本控制

### 7.1 Spot 实例

```python
estimator = PyTorch(
    # ... 其他配置 ...
    use_spot_instances=True,
    max_wait=7200,    # 最长等待时间（秒）
    max_run=3600,     # 最长运行时间（秒）
)
```

| 实例类型      | 按需价格     | Spot 价格（约） | 节省比例 |
| ------------- | ------------ | --------------- | -------- |
| ml.p3.2xlarge | ~$3.82/小时  | ~$1.15/小时     | 70%      |
| ml.p3.8xlarge | ~$14.69/小时 | ~$4.40/小时     | 70%      |

### 7.2 成本优化策略

| 策略               | 说明                           |
| ------------------ | ------------------------------ |
| **Spot 实例**      | 容错训练使用 Spot              |
| **Checkpoint**     | 启用 Checkpoint 防止 Spot 中断 |
| **合适的实例**     | 避免过度配置                   |
| **超时设置**       | 设置 max_run 防止失控          |
| **Early Stopping** | HPO 启用早停                   |

---

## 8. 模型注册

### 8.1 训练后注册模型

```python
from sagemaker.model import Model

model = Model(
    image_uri=estimator.training_image_uri(),
    model_data=estimator.model_data,
    role='arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole',
    name='{team}-{project}-model-v1'
)

# 注册到 Model Registry
model_package = model.register(
    content_types=['application/json'],
    response_types=['application/json'],
    inference_instances=['ml.m5.xlarge'],
    transform_instances=['ml.m5.xlarge'],
    model_package_group_name='{team}-{project}-models',
    approval_status='PendingManualApproval'
)
```

---

## 9. CLI 命令

### 9.1 查看 Training Jobs

```bash
# 列出 Training Jobs
aws sagemaker list-training-jobs \
  --sort-by CreationTime \
  --sort-order Descending \
  --max-results 20

# 查看 Job 详情
aws sagemaker describe-training-job \
  --training-job-name {job-name}
```

### 9.2 停止 Training Job

```bash
aws sagemaker stop-training-job \
  --training-job-name {job-name}
```

---

## 10. 待完善内容

- [ ] 自定义容器训练配置
- [ ] SageMaker Experiments 集成
- [ ] Model Registry 详细配置
- [ ] Pipeline 集成示例

---

## 11. 检查清单

### 训练前

- [ ] Execution Role 有训练相关权限
- [ ] 训练数据已上传到 S3
- [ ] 训练脚本已准备
- [ ] 选择合适的实例类型

### 提交 Job

- [ ] 使用正确的命名规范
- [ ] 配置超参数
- [ ] 设置超时时间
- [ ] 添加标签
- [ ] （可选）启用 Spot 实例

### 训练后

- [ ] 检查训练指标
- [ ] 验证模型产物
- [ ] 注册模型（如需要）
- [ ] 清理训练中间文件

