# 12 - SageMaker Training

> 模型训练 Job 快速入门指南

---

## 快速开始

> ✅ **前提条件**：已完成 Phase 1 基础设施部署，可登录 SageMaker Studio

### 环境准备

在 SageMaker Studio JupyterLab 中运行：

```python
import sagemaker
import boto3
from sagemaker.sklearn import SKLearn
from sagemaker.xgboost import XGBoost

# 获取当前环境信息
session = sagemaker.Session()
region = session.boto_region_name
account_id = boto3.client('sts').get_caller_identity()['Account']

# 项目配置（根据实际项目修改）
COMPANY = "acme"
TEAM = "rc"
PROJECT = "fraud-detection"
TEAM_FULLNAME = "RiskControl"
PROJECT_CAMEL = "FraudDetection"

# 自动构建资源名称（4 角色设计）
# Training Job 使用 TrainingRole
ROLE_NAME = f"SageMaker-{TEAM_FULLNAME}-{PROJECT_CAMEL}-TrainingRole"
ROLE_ARN = f"arn:aws:iam::{account_id}:role/{COMPANY}-sagemaker/{ROLE_NAME}"
BUCKET = f"{COMPANY}-sm-{TEAM}-{PROJECT}"

print(f"Region: {region}")
print(f"Training Role ARN: {ROLE_ARN}")
print(f"S3 Bucket: s3://{BUCKET}/")
```

---

## 1. Training 概述

### 1.1 什么是 SageMaker Training

SageMaker Training 提供托管的模型训练基础设施：

- **托管计算**：无需管理服务器
- **分布式训练**：支持多机多卡
- **内置算法**：XGBoost、线性学习器等
- **自定义脚本**：支持 PyTorch、TensorFlow 等
- **超参数调优**：自动化调参（HPO）

### 1.2 适用场景

| 场景          | 推荐工具         | 说明           |
| ------------- | ---------------- | -------------- |
| 模型原型开发  | Studio Notebook  | 快速迭代、调试 |
| 正式模型训练  | **Training Job** | 可复现、可追溯 |
| 超参数搜索    | HPO Job          | 自动化调参     |
| Pipeline 集成 | Training Step    | ML Pipeline    |

### 1.3 训练模式

| 模式           | 说明         | 适用场景           |
| -------------- | ------------ | ------------------ |
| **单机单卡**   | 1 实例       | 小数据集、快速验证 |
| **单机多卡**   | 1 实例多 GPU | 中等规模           |
| **多机分布式** | 多实例并行   | 大规模训练         |

---

## 2. 完整示例：XGBoost 训练

### 2.1 准备训练数据

```python
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split

# 创建示例数据
np.random.seed(42)
n_samples = 10000

df = pd.DataFrame({
    'feature_1': np.random.randn(n_samples),
    'feature_2': np.random.randn(n_samples),
    'feature_3': np.random.exponential(1, n_samples),
    'category': np.random.choice(['A', 'B', 'C'], n_samples)
})

# 创建标签
df['label'] = ((df['feature_1'] + df['feature_2'] * 0.5 +
               np.random.randn(n_samples) * 0.3) > 0).astype(int)

# One-hot 编码
df = pd.get_dummies(df, columns=['category'], drop_first=True)

# 分割数据
train_df, test_df = train_test_split(df, test_size=0.2, random_state=42)

# 保存为 CSV（XGBoost 要求标签在第一列）
cols = ['label'] + [c for c in train_df.columns if c != 'label']
train_df[cols].to_csv('train.csv', index=False, header=False)
test_df[cols].to_csv('test.csv', index=False, header=False)

# 上传到 S3
train_path = session.upload_data('train.csv', bucket=BUCKET, key_prefix='training/input/train')
test_path = session.upload_data('test.csv', bucket=BUCKET, key_prefix='training/input/test')

print(f"Train data: {train_path}")
print(f"Test data: {test_path}")
```

### 2.2 使用内置 XGBoost 算法

```python
from sagemaker.inputs import TrainingInput

# 获取 XGBoost 镜像 URI
xgboost_container = sagemaker.image_uris.retrieve(
    framework='xgboost',
    region=region,
    version='1.7-1'
)

# 创建 Estimator
xgb_estimator = sagemaker.estimator.Estimator(
    image_uri=xgboost_container,
    role=ROLE_ARN,
    instance_count=1,
    instance_type='ml.m5.xlarge',
    output_path=f's3://{BUCKET}/training/output/',
    base_job_name=f'{TEAM}-{PROJECT}-xgb',
    sagemaker_session=session,
    max_run=3600,  # 1 小时超时
    tags=[
        {'Key': 'Team', 'Value': TEAM},
        {'Key': 'Project', 'Value': PROJECT}
    ]
)

# 设置超参数
xgb_estimator.set_hyperparameters(
    objective='binary:logistic',
    num_round=100,
    max_depth=5,
    eta=0.2,
    gamma=4,
    min_child_weight=6,
    subsample=0.8,
    eval_metric='auc'
)

# 定义数据输入
train_input = TrainingInput(
    s3_data=f's3://{BUCKET}/training/input/train/',
    content_type='text/csv'
)

validation_input = TrainingInput(
    s3_data=f's3://{BUCKET}/training/input/test/',
    content_type='text/csv'
)

# 启动训练
xgb_estimator.fit({
    'train': train_input,
    'validation': validation_input
})

print(f"Model artifact: {xgb_estimator.model_data}")
```

---

## 3. 完整示例：自定义 SKLearn 训练

### 3.1 准备训练脚本

创建 `train.py`：

```python
# train.py - SKLearn 训练脚本
import os
import argparse
import joblib
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, roc_auc_score

def main():
    # 解析参数
    parser = argparse.ArgumentParser()

    # 超参数
    parser.add_argument('--n-estimators', type=int, default=100)
    parser.add_argument('--max-depth', type=int, default=10)
    parser.add_argument('--min-samples-split', type=int, default=2)

    # SageMaker 环境变量
    parser.add_argument('--model-dir', type=str, default=os.environ.get('SM_MODEL_DIR'))
    parser.add_argument('--train', type=str, default=os.environ.get('SM_CHANNEL_TRAIN'))
    parser.add_argument('--test', type=str, default=os.environ.get('SM_CHANNEL_TEST'))

    args = parser.parse_args()

    print(f"Hyperparameters: n_estimators={args.n_estimators}, max_depth={args.max_depth}")

    # 加载训练数据
    train_files = [f for f in os.listdir(args.train) if f.endswith('.csv')]
    train_df = pd.concat([pd.read_csv(os.path.join(args.train, f)) for f in train_files])

    # 分离特征和标签（假设第一列是标签）
    y_train = train_df.iloc[:, 0]
    X_train = train_df.iloc[:, 1:]

    print(f"Training data shape: {X_train.shape}")

    # 创建并训练模型
    model = RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        min_samples_split=args.min_samples_split,
        random_state=42,
        n_jobs=-1
    )

    model.fit(X_train, y_train)

    # 在测试集上评估
    if args.test:
        test_files = [f for f in os.listdir(args.test) if f.endswith('.csv')]
        test_df = pd.concat([pd.read_csv(os.path.join(args.test, f)) for f in test_files])

        y_test = test_df.iloc[:, 0]
        X_test = test_df.iloc[:, 1:]

        predictions = model.predict(X_test)
        probabilities = model.predict_proba(X_test)[:, 1]

        accuracy = accuracy_score(y_test, predictions)
        auc = roc_auc_score(y_test, probabilities)

        print(f"Test Accuracy: {accuracy:.4f}")
        print(f"Test AUC: {auc:.4f}")

    # 保存模型
    model_path = os.path.join(args.model_dir, 'model.joblib')
    joblib.dump(model, model_path)
    print(f"Model saved to: {model_path}")

if __name__ == '__main__':
    main()
```

### 3.2 提交 SKLearn Training Job

```python
from sagemaker.sklearn import SKLearn
from sagemaker.inputs import TrainingInput

# 创建 SKLearn Estimator
sklearn_estimator = SKLearn(
    entry_point='train.py',
    role=ROLE_ARN,
    instance_count=1,
    instance_type='ml.m5.xlarge',
    framework_version='1.2-1',
    py_version='py3',
    output_path=f's3://{BUCKET}/training/output/',
    base_job_name=f'{TEAM}-{PROJECT}-sklearn',
    sagemaker_session=session,
    max_run=3600,
    hyperparameters={
        'n-estimators': 200,
        'max-depth': 15,
        'min-samples-split': 5
    },
    tags=[
        {'Key': 'Team', 'Value': TEAM},
        {'Key': 'Project', 'Value': PROJECT}
    ]
)

# 启动训练
sklearn_estimator.fit({
    'train': f's3://{BUCKET}/training/input/train/',
    'test': f's3://{BUCKET}/training/input/test/'
})

print(f"Model artifact: {sklearn_estimator.model_data}")
```

---

## 4. 超参数调优（HPO）

### 4.1 定义 HPO Job

```python
from sagemaker.tuner import (
    IntegerParameter,
    ContinuousParameter,
    HyperparameterTuner
)

# 定义超参数范围
hyperparameter_ranges = {
    'n-estimators': IntegerParameter(50, 300),
    'max-depth': IntegerParameter(5, 20),
    'min-samples-split': IntegerParameter(2, 10)
}

# 创建 Tuner
tuner = HyperparameterTuner(
    estimator=sklearn_estimator,
    objective_metric_name='Test AUC',
    objective_type='Maximize',
    hyperparameter_ranges=hyperparameter_ranges,
    metric_definitions=[
        {'Name': 'Test AUC', 'Regex': 'Test AUC: ([0-9\\.]+)'}
    ],
    max_jobs=10,
    max_parallel_jobs=2,
    base_tuning_job_name=f'{TEAM}-{PROJECT}-hpo'
)

# 启动 HPO
tuner.fit({
    'train': f's3://{BUCKET}/training/input/train/',
    'test': f's3://{BUCKET}/training/input/test/'
})

# 获取最佳模型
best_job = tuner.best_training_job()
print(f"Best training job: {best_job}")
```

---

## 5. 数据路径规范

### 5.1 S3 目录结构

```
s3://{company}-sm-{team}-{project}/
├── training/
│   ├── input/
│   │   ├── train/          # 训练数据
│   │   └── test/           # 测试数据
│   └── output/
│       └── {job-name}/     # 模型产物
├── models/
│   └── {model-name}/       # 部署用模型
└── processed/              # 处理后数据
```

### 5.2 Job 命名规范

```
{team}-{project}-{algorithm}-{timestamp}

示例:
- rc-fraud-detection-xgb-20240101-120000
- algo-recommendation-sklearn-20240101-130000
```

---

## 6. 实例类型选择

### 6.1 CPU 训练实例

| 数据规模  | 推荐实例      | 配置           | 参考价格 |
| --------- | ------------- | -------------- | -------- |
| < 10 GB   | ml.m5.xlarge  | 4 vCPU, 16 GB  | ~$0.23/h |
| 10-50 GB  | ml.m5.2xlarge | 8 vCPU, 32 GB  | ~$0.46/h |
| 50-100 GB | ml.m5.4xlarge | 16 vCPU, 64 GB | ~$0.92/h |

### 6.2 GPU 训练实例（深度学习）

| 场景     | 推荐实例        | GPU     | 参考价格 |
| -------- | --------------- | ------- | -------- |
| 小模型   | ml.g4dn.xlarge  | 1x T4   | ~$0.74/h |
| 中等模型 | ml.g4dn.2xlarge | 1x T4   | ~$1.05/h |
| 大模型   | ml.p3.2xlarge   | 1x V100 | ~$3.83/h |

---

## 7. 成本控制

### 7.1 最佳实践

| 策略          | 说明           | 节省     |
| ------------- | -------------- | -------- |
| **Spot 实例** | 可中断训练     | 60-90%   |
| **设置超时**  | `max_run=3600` | 避免失控 |
| **合适实例**  | 不要过度配置   | 30-50%   |

### 7.2 启用 Spot 训练

```python
estimator = SKLearn(
    # ... 其他配置 ...
    use_spot_instances=True,
    max_wait=7200,  # 最大等待时间（含排队）
    max_run=3600,   # 最大运行时间
)
```

### 7.3 停止运行中的 Job

```bash
# CLI 方式
aws sagemaker stop-training-job --training-job-name {job-name}
```

---

## 8. 监控与日志

### 8.1 CloudWatch Logs

Training Job 日志自动写入：

```
/aws/sagemaker/TrainingJobs/{job-name}/algo-1-{timestamp}
```

### 8.2 查看训练指标

```python
# 获取训练指标
from sagemaker.analytics import TrainingJobAnalytics

analytics = TrainingJobAnalytics(training_job_name=xgb_estimator.latest_training_job.name)
df = analytics.dataframe()
print(df)
```

---

## 9. CLI 快速参考

```bash
# 列出 Training Jobs
aws sagemaker list-training-jobs \
  --sort-by CreationTime \
  --sort-order Descending \
  --max-results 10

# 查看 Job 详情
aws sagemaker describe-training-job \
  --training-job-name {job-name}

# 停止 Job
aws sagemaker stop-training-job \
  --training-job-name {job-name}

# 查看 HPO Job
aws sagemaker describe-hyper-parameter-tuning-job \
  --hyper-parameter-tuning-job-name {hpo-job-name}
```

---

## 10. 故障排查

### 常见问题

| 问题                    | 原因          | 解决方案                      |
| ----------------------- | ------------- | ----------------------------- |
| `AccessDenied`          | Role 权限不足 | 确认使用正确的 Execution Role |
| `AlgorithmError`        | 训练脚本错误  | 检查 CloudWatch Logs          |
| `ResourceLimitExceeded` | 实例配额不足  | 申请 Service Quota 增加       |
| 训练很慢                | 实例过小      | 使用更大实例或 GPU            |

### 调试训练脚本

```python
# 本地测试（在 Notebook 中）
import subprocess

# 模拟 SageMaker 环境变量
os.environ['SM_MODEL_DIR'] = '/tmp/model'
os.environ['SM_CHANNEL_TRAIN'] = '/tmp/train'
os.environ['SM_CHANNEL_TEST'] = '/tmp/test'

# 运行脚本
exec(open('train.py').read())
```

---

## 11. 检查清单

### ✅ 提交 Job 前

- [ ] Execution Role 存在且有 `AmazonSageMakerFullAccess`
- [ ] 训练数据已上传到 S3
- [ ] 训练脚本语法正确
- [ ] 选择合适的实例类型

### ✅ Job 运行中

- [ ] 监控 CloudWatch Logs
- [ ] 检查训练指标

### ✅ Job 完成后

- [ ] 下载模型产物
- [ ] 评估模型性能
- [ ] 记录超参数和指标

---

## 下一步

- [13 - 实时推理](13-realtime-inference.md) - 模型部署
- [10 - SageMaker Processing](10-sagemaker-processing.md) - 数据处理
