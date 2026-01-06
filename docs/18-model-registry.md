# 18 - SageMaker Model Registry

> **用途**：为每个项目创建 Model Package Group，实现模型版本管理  
> **脚本位置**：`scripts/07-model-registry/`

---

## 📋 概述

本模块创建 SageMaker Model Registry 资源，用于：

- **模型版本管理**: 追踪每个模型的不同版本
- **模型审批流程**: Pending → Approved → Rejected
- **模型元数据**: 记录模型性能指标、训练参数等
- **模型部署追踪**: 关联模型与 Endpoint

---

## 🏗️ 创建的资源

为每个项目创建一个 Model Package Group：

| Group Name                   | 项目                          |
| ---------------------------- | ----------------------------- |
| `rc-fraud-detection`         | Risk Control / Fraud Detection |
| `rc-anti-money-laundering`   | Risk Control / AML            |
| `algo-recommendation-engine` | Algorithm / Recommendation    |

命名规则: `{team}-{project}`

---

## ⚙️ 配置

在 `.env.shared` 中配置：

```bash
# Model Registry 配置
ENABLE_MODEL_REGISTRY=true   # 是否启用 Model Registry 模块
```

Model Package Groups 根据 `TEAMS` 和 `{TEAM}_PROJECTS` 配置自动创建。

---

## 🚀 使用方法

### 快速设置

```bash
cd scripts/07-model-registry
./setup-all.sh
```

### 分步执行

```bash
# 1. 创建 Model Package Groups
./01-create-model-groups.sh

# 2. 验证
./verify.sh
```

---

## 📦 模型注册使用

### 1. 注册模型到 Model Registry

```python
from sagemaker import Model
from sagemaker.model_metrics import ModelMetrics, MetricsSource

# 创建 Model 对象
model = Model(
    image_uri="123456789012.dkr.ecr.region.amazonaws.com/image:tag",
    model_data="s3://bucket/model.tar.gz",
    role=execution_role,
)

# 定义模型指标
model_metrics = ModelMetrics(
    model_statistics=MetricsSource(
        s3_uri="s3://bucket/metrics/statistics.json",
        content_type="application/json",
    ),
)

# 注册到 Model Registry
model_package = model.register(
    model_package_group_name="rc-fraud-detection",
    content_types=["application/json"],
    response_types=["application/json"],
    inference_instances=["ml.m5.large", "ml.m5.xlarge"],
    transform_instances=["ml.m5.xlarge"],
    model_metrics=model_metrics,
    approval_status="PendingManualApproval",
    description="Fraud detection model v1.0",
)

print(f"Model registered: {model_package.model_package_arn}")
```

### 2. 列出模型版本

```bash
aws sagemaker list-model-packages \
    --model-package-group-name rc-fraud-detection \
    --region ap-northeast-1 \
    --query 'ModelPackageSummaryList[].{ARN:ModelPackageArn,Status:ModelApprovalStatus,Created:CreationTime}' \
    --output table
```

### 3. 批准模型

```bash
# 批准
aws sagemaker update-model-package \
    --model-package-arn "arn:aws:sagemaker:region:account:model-package/rc-fraud-detection/1" \
    --model-approval-status Approved

# 拒绝
aws sagemaker update-model-package \
    --model-package-arn "arn:aws:sagemaker:region:account:model-package/rc-fraud-detection/1" \
    --model-approval-status Rejected \
    --approval-description "Performance below threshold"
```

### 4. 从 Model Registry 部署模型

```python
from sagemaker import ModelPackage

# 从 Model Package 创建模型
model = ModelPackage(
    role=execution_role,
    model_package_arn="arn:aws:sagemaker:region:account:model-package/rc-fraud-detection/1",
)

# 部署到 Endpoint
predictor = model.deploy(
    initial_instance_count=1,
    instance_type="ml.m5.large",
    endpoint_name="fraud-detection-endpoint",
)
```

---

## 🔄 模型审批流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         模型审批工作流                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Training Job                                                          │
│       │                                                                 │
│       ▼                                                                 │
│   ┌─────────────────────────────────────────────┐                      │
│   │ register() with                              │                      │
│   │ approval_status="PendingManualApproval"      │                      │
│   └─────────────────────────────────────────────┘                      │
│       │                                                                 │
│       ▼                                                                 │
│   ┌─────────────────┐                                                   │
│   │ Model Version   │                                                   │
│   │ Status: Pending │                                                   │
│   └────────┬────────┘                                                   │
│            │                                                            │
│       ┌────┴────┐                                                       │
│       │ Review  │ ← 人工审核 / 自动化测试                               │
│       └────┬────┘                                                       │
│            │                                                            │
│      ┌─────┴─────┐                                                      │
│      ▼           ▼                                                      │
│ ┌─────────┐ ┌─────────┐                                                 │
│ │Approved │ │Rejected │                                                 │
│ └────┬────┘ └─────────┘                                                 │
│      │                                                                  │
│      ▼                                                                  │
│ ┌─────────────────────────────────────────────┐                        │
│ │ deploy() to Endpoint                         │                        │
│ └─────────────────────────────────────────────┘                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 IAM 权限

Execution Role 需要以下权限（已在 Phase 1 配置）：

```json
{
    "Effect": "Allow",
    "Action": [
        "sagemaker:CreateModelPackage",
        "sagemaker:CreateModelPackageGroup",
        "sagemaker:DescribeModelPackage",
        "sagemaker:DescribeModelPackageGroup",
        "sagemaker:ListModelPackages",
        "sagemaker:ListModelPackageGroups",
        "sagemaker:UpdateModelPackage"
    ],
    "Resource": [
        "arn:aws:sagemaker:${REGION}:${ACCOUNT}:model-package-group/${TEAM}-${PROJECT}",
        "arn:aws:sagemaker:${REGION}:${ACCOUNT}:model-package/${TEAM}-${PROJECT}/*"
    ]
}
```

---

## 🗑️ 清理

```bash
# ⚠️ 会删除所有 Model Package Groups 和模型版本
cd scripts/07-model-registry
./cleanup.sh
```

---

## 🔗 相关文档

- [12 - Training 模型训练](./12-sagemaker-training.md) - 训练模型
- [13 - Inference 实时推理](./13-realtime-inference.md) - 部署模型
- [17 - ECR 容器镜像](./17-ecr.md) - 自定义镜像

