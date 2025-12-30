# 10 - SageMaker Processing

> 数据处理 Job 快速入门指南

---

## 快速开始

> ✅ **前提条件**：已完成 Phase 1 基础设施部署（01-iam ~ 06-spaces）

### 环境准备

在 SageMaker Studio JupyterLab 中运行：

```python
import sagemaker
import boto3
from sagemaker.sklearn.processing import SKLearnProcessor
from sagemaker.processing import ProcessingInput, ProcessingOutput

# 获取当前环境信息
session = sagemaker.Session()
region = session.boto_region_name
account_id = boto3.client('sts').get_caller_identity()['Account']

# 项目配置（根据实际项目修改）
COMPANY = "acme"
TEAM = "rc"
PROJECT = "fraud-detection"

# 自动构建资源名称
ROLE_NAME = f"SageMaker-RiskControl-FraudDetection-ExecutionRole"
ROLE_ARN = f"arn:aws:iam::{account_id}:role/{COMPANY}-sagemaker/{ROLE_NAME}"
BUCKET = f"{COMPANY}-sm-{TEAM}-{PROJECT}"

print(f"Region: {region}")
print(f"Role ARN: {ROLE_ARN}")
print(f"S3 Bucket: s3://{BUCKET}/")
```

---

## 1. Processing 概述

### 1.1 什么是 SageMaker Processing

SageMaker Processing 提供托管的数据处理基础设施：

- **数据预处理**：清洗、转换、特征工程
- **后处理**：模型评估、结果分析
- **批量推理**：大规模离线预测

### 1.2 适用场景

| 场景 | 推荐工具 | 说明 |
|------|----------|------|
| 交互式探索 | Studio Notebook | 快速迭代、可视化 |
| 生产级数据处理 | **Processing Job** | 可复现、可调度、大规模 |
| 特征工程 Pipeline | Processing + Step Functions | 编排多步骤处理 |

### 1.3 Processing 类型

| 类型 | 说明 | 适用场景 |
|------|------|----------|
| **SKLearn** | scikit-learn 环境 | 通用数据处理（推荐入门） |
| **Spark** | Apache Spark 集群 | 大规模数据处理（>100GB） |
| **PyTorch/TF** | 深度学习框架 | 特征嵌入、向量化 |
| **Custom Container** | 自定义镜像 | 特殊依赖 |

---

## 2. 完整示例：SKLearn Processing

### 2.1 准备处理脚本

创建 `preprocessing.py`：

```python
# preprocessing.py - 数据预处理脚本
import os
import pandas as pd
import argparse

def main():
    # 解析参数
    parser = argparse.ArgumentParser()
    parser.add_argument('--train-ratio', type=float, default=0.8)
    args = parser.parse_args()
    
    # SageMaker Processing 标准路径
    input_path = '/opt/ml/processing/input'
    output_path = '/opt/ml/processing/output'
    
    print(f"Reading data from: {input_path}")
    
    # 读取所有 CSV 文件
    all_files = [f for f in os.listdir(input_path) if f.endswith('.csv')]
    df_list = [pd.read_csv(os.path.join(input_path, f)) for f in all_files]
    df = pd.concat(df_list, ignore_index=True)
    
    print(f"Total records: {len(df)}")
    
    # 数据处理示例
    # 1. 删除缺失值
    df = df.dropna()
    
    # 2. 特征工程（示例）
    if 'amount' in df.columns:
        df['amount_log'] = df['amount'].apply(lambda x: max(0, x)).apply(np.log1p)
    
    # 3. 分割训练/测试集
    train_size = int(len(df) * args.train_ratio)
    train_df = df[:train_size]
    test_df = df[train_size:]
    
    # 保存结果
    os.makedirs(output_path, exist_ok=True)
    train_df.to_csv(f'{output_path}/train.csv', index=False)
    test_df.to_csv(f'{output_path}/test.csv', index=False)
    
    print(f"Train set: {len(train_df)} records")
    print(f"Test set: {len(test_df)} records")
    print("Processing complete!")

if __name__ == '__main__':
    import numpy as np
    main()
```

### 2.2 上传测试数据

```python
# 上传示例数据到 S3
import pandas as pd
import numpy as np

# 创建示例数据
np.random.seed(42)
df = pd.DataFrame({
    'transaction_id': range(1000),
    'amount': np.random.exponential(100, 1000),
    'category': np.random.choice(['A', 'B', 'C'], 1000),
    'is_fraud': np.random.choice([0, 1], 1000, p=[0.95, 0.05])
})

# 保存并上传
df.to_csv('sample_data.csv', index=False)
session.upload_data('sample_data.csv', bucket=BUCKET, key_prefix='raw/uploads')
print(f"Data uploaded to s3://{BUCKET}/raw/uploads/sample_data.csv")
```

### 2.3 提交 Processing Job

```python
from sagemaker.sklearn.processing import SKLearnProcessor
from sagemaker.processing import ProcessingInput, ProcessingOutput
from sagemaker.network import NetworkConfig

# 获取 VPC 配置（可选，用于 VPC 内运行）
# 如果不需要 VPC 隔离，可以省略 network_config

# 创建 Processor
sklearn_processor = SKLearnProcessor(
    framework_version='1.2-1',
    role=ROLE_ARN,
    instance_type='ml.m5.xlarge',
    instance_count=1,
    base_job_name=f'{TEAM}-{PROJECT}-preprocess',
    sagemaker_session=session,
    max_runtime_in_seconds=3600,  # 1 小时超时
    tags=[
        {'Key': 'Team', 'Value': TEAM},
        {'Key': 'Project', 'Value': PROJECT}
    ]
)

# 提交 Job
sklearn_processor.run(
    code='preprocessing.py',
    inputs=[
        ProcessingInput(
            source=f's3://{BUCKET}/raw/uploads/',
            destination='/opt/ml/processing/input'
        )
    ],
    outputs=[
        ProcessingOutput(
            source='/opt/ml/processing/output',
            destination=f's3://{BUCKET}/processed/latest/'
        )
    ],
    arguments=['--train-ratio', '0.8']
)

print("Processing job submitted!")
print(f"Job name: {sklearn_processor.latest_job_name}")
```

### 2.4 监控 Job 状态

```python
# 方式 1：等待完成
sklearn_processor.jobs[-1].wait()

# 方式 2：查询状态
job_name = sklearn_processor.latest_job_name
sm_client = boto3.client('sagemaker')
response = sm_client.describe_processing_job(ProcessingJobName=job_name)
print(f"Status: {response['ProcessingJobStatus']}")
```

---

## 3. 数据路径规范

### 3.1 S3 目录结构

```
s3://{company}-sm-{team}-{project}/
├── raw/                    # 原始数据
│   └── uploads/           # 上传的原始文件
├── processed/              # 处理后数据
│   └── {job-name}/        # 按 Job 组织
├── features/               # 特征数据
│   └── v{version}/        # 版本化
└── models/                 # 模型产物
    └── {model-name}/
```

### 3.2 Job 命名规范

```
{team}-{project}-{job-type}-{timestamp}

示例:
- rc-fraud-detection-preprocess-20240101-120000
- algo-recommendation-feature-eng-20240101-130000
```

---

## 4. 实例类型选择

| 数据规模 | 推荐实例 | 配置 | 参考价格 |
|----------|----------|------|----------|
| < 10 GB | ml.m5.xlarge | 4 vCPU, 16 GB | ~$0.23/h |
| 10-50 GB | ml.m5.2xlarge | 8 vCPU, 32 GB | ~$0.46/h |
| 50-100 GB | ml.m5.4xlarge | 16 vCPU, 64 GB | ~$0.92/h |
| > 100 GB | Spark Processing | 分布式 | 视集群大小 |

---

## 5. VPC 配置（可选）

如需在 VPC 内运行 Processing Job：

```python
from sagemaker.network import NetworkConfig

# 使用与 Studio 相同的 VPC 配置
network_config = NetworkConfig(
    enable_network_isolation=False,
    security_group_ids=['sg-xxxxxxxx'],  # SageMaker Studio 安全组
    subnets=['subnet-xxxxxxxx', 'subnet-yyyyyyyy']  # 私有子网
)

sklearn_processor = SKLearnProcessor(
    # ... 其他配置 ...
    network_config=network_config
)
```

---

## 6. 成本控制

### 6.1 最佳实践

| 策略 | 说明 | 节省 |
|------|------|------|
| **设置超时** | `max_runtime_in_seconds=3600` | 避免失控任务 |
| **合适实例** | 不要过度配置 | 30-50% |
| **及时停止** | 不再需要时停止 Job | 100% |

### 6.2 停止运行中的 Job

```bash
# CLI 方式
aws sagemaker stop-processing-job --processing-job-name {job-name}
```

```python
# SDK 方式
sm_client.stop_processing_job(ProcessingJobName=job_name)
```

---

## 7. 监控与日志

### 7.1 CloudWatch Logs

Processing Job 日志自动写入：

```
/aws/sagemaker/ProcessingJobs/{job-name}
```

### 7.2 在 Notebook 中查看日志

```python
# 获取 Job 日志
import boto3

logs_client = boto3.client('logs')
log_group = f'/aws/sagemaker/ProcessingJobs'

# 列出日志流
response = logs_client.describe_log_streams(
    logGroupName=log_group,
    logStreamNamePrefix=job_name
)

for stream in response['logStreams']:
    print(stream['logStreamName'])
```

---

## 8. CLI 快速参考

```bash
# 列出 Processing Jobs
aws sagemaker list-processing-jobs \
  --sort-by CreationTime \
  --sort-order Descending \
  --max-results 10

# 查看 Job 详情
aws sagemaker describe-processing-job \
  --processing-job-name {job-name}

# 停止 Job
aws sagemaker stop-processing-job \
  --processing-job-name {job-name}
```

---

## 9. 故障排查

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `AccessDenied` | Role 权限不足 | 确认使用正确的 Execution Role |
| `ResourceLimitExceeded` | 实例配额不足 | 申请 Service Quota 增加 |
| `ValidationException` | 参数错误 | 检查 S3 路径、实例类型 |
| Job 超时 | 数据量大/实例小 | 增大实例或设置更长超时 |

### 检查 Role 权限

```python
# 验证 Role 存在
iam = boto3.client('iam')
try:
    response = iam.get_role(RoleName=ROLE_NAME)
    print(f"Role exists: {response['Role']['Arn']}")
except iam.exceptions.NoSuchEntityException:
    print("Role not found!")
```

---

## 10. 检查清单

### ✅ 提交 Job 前

- [ ] Execution Role 存在且有 `AmazonSageMakerFullAccess`
- [ ] S3 输入数据已上传
- [ ] 处理脚本已准备
- [ ] 选择合适的实例类型

### ✅ Job 运行中

- [ ] 监控 CloudWatch Logs
- [ ] 检查资源使用率

### ✅ Job 完成后

- [ ] 验证输出数据
- [ ] 清理不需要的临时文件
- [ ] 记录 Job 配置供复用

---

## 下一步

- [11 - Data Wrangler](11-data-wrangler.md) - 可视化数据准备
- [12 - SageMaker Training](12-sagemaker-training.md) - 模型训练
