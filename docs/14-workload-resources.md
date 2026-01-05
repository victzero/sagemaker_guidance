# 14 - 工作负载资源设计

> Processing / Training / Inference 阶段的资源规划与设计

---

## 1. 概述

### 1.1 基础设施 vs 工作负载资源对比

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         资源分层架构                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  基础设施 (必需)                                                            │
│  ═══════════════                                                            │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐              │
│  │   IAM   │ │   VPC   │ │   S3    │ │ Domain  │ │ Profile │              │
│  │ Users   │ │Endpoints│ │ Buckets │ │         │ │ +Space  │              │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘              │
│                                                                             │
│  工作负载资源 (本文档)                                                      │
│  ═══════════════════                                                        │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐              │
│  │Workload │ │   ECR   │ │ Model   │ │   KMS   │ │ Logs    │              │
│  │   SGs   │ │  Repos  │ │Registry │ │  Keys   │ │ Groups  │              │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 各阶段资源需求

| 资源类型       | Processing | Training | Inference | 备注                        |
| -------------- | :--------: | :------: | :-------: | --------------------------- |
| Execution Role |     ✅     |    ✅    |    ✅     | 基础设施已创建项目级 Role   |
| S3 Bucket      |     ✅     |    ✅    |    ✅     | 基础设施已创建项目级 Bucket |
| VPC/Subnet     |     ✅     |    ✅    |    ✅     | 基础设施已配置              |
| Security Group |     ✅     |    ✅    |    ✅     | **需补充工作负载 SG**       |
| ECR Repository |    可选    |   可选   |    ✅     | **需新建**                  |
| Model Registry |     -      |    ✅    |    ✅     | **需新建**                  |
| KMS Key        |    可选    |   可选   |   可选    | 按需配置                    |

---

## 2. Security Group 设计

### 2.1 设计原则

**按用途分离，而非按项目分离**

```
推荐设计 (用途级):
┌──────────────────────────────────────────────────────────────────┐
│  {TAG_PREFIX}-studio     │ Studio 交互式开发                     │
│  {TAG_PREFIX}-training   │ Training Jobs                        │
│  {TAG_PREFIX}-processing │ Processing Jobs                      │
│  {TAG_PREFIX}-inference  │ Inference Endpoints                  │
│  {TAG_PREFIX}-vpc-endpoints │ VPC Endpoints (已有)              │
└──────────────────────────────────────────────────────────────────┘

为什么不按项目分:
1. 项目隔离已通过 Execution Role + S3 实现
2. 安全组主要控制网络边界，非数据访问
3. 减少安全组数量，降低管理复杂度
4. AWS 限制：每个 VPC 最多 500 个安全组
```

### 2.2 安全组规则设计

#### 2.2.1 Training Jobs SG

**名称**: `{TAG_PREFIX}-training`

| 方向 | 类型        | 协议 | 端口 | 来源/目标 | 说明           |
| ---- | ----------- | ---- | ---- | --------- | -------------- |
| 入站 | All Traffic | All  | All  | 自身 SG   | 分布式训练通信 |
| 入站 | HTTPS       | TCP  | 443  | VPC CIDR  | 内部 API       |
| 出站 | HTTPS       | TCP  | 443  | 0.0.0.0/0 | AWS 服务       |
| 出站 | All Traffic | All  | All  | 自身 SG   | 分布式训练通信 |

#### 2.2.2 Processing Jobs SG

**名称**: `{TAG_PREFIX}-processing`

| 方向 | 类型        | 协议 | 端口 | 来源/目标 | 说明           |
| ---- | ----------- | ---- | ---- | --------- | -------------- |
| 入站 | All Traffic | All  | All  | 自身 SG   | Spark 集群通信 |
| 入站 | HTTPS       | TCP  | 443  | VPC CIDR  | 内部 API       |
| 出站 | HTTPS       | TCP  | 443  | 0.0.0.0/0 | AWS 服务       |
| 出站 | All Traffic | All  | All  | 自身 SG   | Spark 集群通信 |

#### 2.2.3 Inference Endpoints SG

**名称**: `{TAG_PREFIX}-inference`

| 方向 | 类型   | 协议 | 端口 | 来源/目标 | 说明         |
| ---- | ------ | ---- | ---- | --------- | ------------ |
| 入站 | HTTPS  | TCP  | 443  | VPC CIDR  | 推理请求     |
| 入站 | Custom | TCP  | 8080 | VPC CIDR  | 推理容器端口 |
| 出站 | HTTPS  | TCP  | 443  | 0.0.0.0/0 | AWS 服务     |

### 2.3 安全组使用指引

```python
# Processing Job
from sagemaker.network import NetworkConfig

network_config = NetworkConfig(
    security_group_ids=['sg-processing-xxxxx'],
    subnets=['subnet-private-a', 'subnet-private-b']
)

processor = SKLearnProcessor(
    ...,
    network_config=network_config
)

# Training Job
estimator = SKLearn(
    ...,
    subnets=['subnet-private-a', 'subnet-private-b'],
    security_group_ids=['sg-training-xxxxx']
)

# Inference Endpoint
model.deploy(
    ...,
    vpc_config={
        'SecurityGroupIds': ['sg-inference-xxxxx'],
        'Subnets': ['subnet-private-a', 'subnet-private-b']
    }
)
```

---

## 3. ECR Repository 设计

### 3.1 何时需要 ECR

| 场景                    | 需要 ECR | 说明                   |
| ----------------------- | :------: | ---------------------- |
| 使用 SageMaker 内置算法 |    ❌    | AWS 托管镜像           |
| 使用官方 Framework 容器 |    ❌    | AWS 托管镜像           |
| 需要额外 Python 依赖    | ⚠️ 可选  | 可在代码中 pip install |
| 需要系统级依赖 (apt)    |    ✅    | 必须自定义镜像         |
| 需要特定版本控制        |    ✅    | 推荐使用 ECR           |
| 自定义推理逻辑          |    ✅    | 推荐使用 ECR           |

### 3.2 仓库组织结构

```
ECR Registry: {AWS_ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com
│
├── {COMPANY}-sagemaker-shared/          # Platform 级共享镜像
│   ├── base-sklearn:1.2-1
│   ├── base-pytorch:2.0-gpu
│   └── base-xgboost:1.7-1
│
├── {COMPANY}-sm-{team}-{project}/       # 项目级镜像
│   ├── preprocessing:v1.0
│   ├── training:v1.0
│   └── inference:v1.0
│
└── 命名示例:
    ├── acme-sagemaker-shared/base-sklearn:1.2-1
    ├── acme-sm-rc-fraud-detection/training:v2.1
    └── acme-sm-algo-recommendation/inference:latest
```

### 3.3 镜像标签规范

| 标签格式           | 用途       | 示例                |
| ------------------ | ---------- | ------------------- |
| `latest`           | 开发测试   | `training:latest`   |
| `v{major}.{minor}` | 版本发布   | `training:v1.2`     |
| `{git-sha}`        | CI/CD 追溯 | `training:abc1234`  |
| `{date}`           | 日期标记   | `training:20240101` |

### 3.4 Lifecycle Policy

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

---

## 4. Model Registry 设计

### 4.1 Model Package Group 组织

```
SageMaker Model Registry
│
├── {team}-{project}                    # Model Package Group (项目级)
│   │
│   ├── Version 1                       # Model Package Version
│   │   ├── Model Artifact: s3://bucket/models/v1/model.tar.gz
│   │   ├── Status: PendingManualApproval
│   │   ├── Metrics: { accuracy: 0.85, f1: 0.82 }
│   │   └── Created: 2024-01-01
│   │
│   ├── Version 2
│   │   ├── Model Artifact: s3://bucket/models/v2/model.tar.gz
│   │   ├── Status: Approved ← 生产部署
│   │   ├── Metrics: { accuracy: 0.89, f1: 0.87 }
│   │   └── Created: 2024-01-15
│   │
│   └── Version 3
│       ├── Model Artifact: s3://bucket/models/v3/model.tar.gz
│       ├── Status: Rejected
│       └── Reason: "Performance regression"
│
└── 命名示例:
    ├── rc-fraud-detection
    ├── rc-anti-money-laundering
    └── algo-recommendation-engine
```

### 4.2 Model Package 状态流转

```
┌──────────────┐     ┌──────────────────────┐     ┌──────────────┐
│   训练完成   │────▶│ PendingManualApproval │────▶│   Approved   │
└──────────────┘     └──────────────────────┘     └──────────────┘
                              │                          │
                              │                          │
                              ▼                          ▼
                     ┌──────────────┐           ┌──────────────┐
                     │   Rejected   │           │  生产部署    │
                     └──────────────┘           └──────────────┘
```

### 4.3 Model Package 元数据

```python
# 注册模型到 Registry
from sagemaker.model import ModelPackage

model_package = ModelPackage(
    model_package_group_name='rc-fraud-detection',
    model_data=model_artifact_uri,
    inference_instances=['ml.m5.large', 'ml.m5.xlarge'],
    transform_instances=['ml.m5.xlarge'],
    model_metrics={
        'ModelQuality': {
            'Statistics': {
                'ContentType': 'application/json',
                'S3Uri': f's3://{bucket}/metrics/evaluation.json'
            }
        }
    },
    approval_status='PendingManualApproval',
    description='XGBoost fraud detection model v2',
    customer_metadata_properties={
        'TrainingJobName': training_job_name,
        'GitCommit': git_sha,
        'TrainedBy': user_name
    }
)
```

---

## 5. KMS Key 设计（可选）

### 5.1 加密范围

| 资源     | 默认加密 | KMS 加密 | 说明                     |
| -------- | :------: | :------: | ------------------------ |
| S3 数据  |  SSE-S3  |   可选   | 高安全需求启用 KMS       |
| EBS 卷   |    ✅    |   可选   | Training/Processing 实例 |
| 模型产物 |  SSE-S3  |   可选   | model.tar.gz             |
| ECR 镜像 |    ❌    |   可选   | 容器镜像层               |

### 5.2 KMS Key 组织

```
Platform 级别 (默认，推荐):
└── alias/sagemaker-platform
    └── 所有项目共用，简化管理

项目级别 (高安全需求):
├── alias/sagemaker-rc-fraud
├── alias/sagemaker-rc-aml
└── alias/sagemaker-algo-rec
    └── 各项目独立密钥，细粒度控制
```

### 5.3 Key Policy 示例

```json
{
  "Statement": [
    {
      "Sid": "Allow SageMaker to use the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "sagemaker.amazonaws.com"
      },
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${AWS_ACCOUNT_ID}"
        }
      }
    }
  ]
}
```

---

## 6. CloudWatch Logs 组织

### 6.1 日志组命名规范

```
/aws/sagemaker/
├── ProcessingJobs/                      # 自动创建
│   └── {team}-{project}-preprocess-{timestamp}
│
├── TrainingJobs/                        # 自动创建
│   └── {team}-{project}-xgb-{timestamp}/algo-1-{timestamp}
│
├── Endpoints/                           # 自动创建
│   └── {team}-{project}-{endpoint-name}
│
└── Studio/                              # 自动创建
    └── {domain-id}/{user-profile}
```

### 6.2 日志保留策略

| 日志类型       | 推荐保留期 | 说明         |
| -------------- | ---------- | ------------ |
| ProcessingJobs | 30 天      | 数据处理调试 |
| TrainingJobs   | 90 天      | 模型训练追溯 |
| Endpoints      | 14 天      | 推理监控     |
| Studio         | 7 天       | 开发调试     |

### 6.3 日志洞察查询示例

```sql
-- 查找失败的 Training Jobs
fields @timestamp, @message
| filter @logStream like /algo-1/
| filter @message like /Error|Exception|Failed/
| sort @timestamp desc
| limit 100

-- 统计 Endpoint 延迟
fields @timestamp, @message
| parse @message "ModelLatency: * ms" as latency
| stats avg(latency), max(latency), p99(latency) by bin(5m)
```

---

## 7. 资源关系总览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         完整资源架构                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Platform 级别 (共享):                                                     │
│   ═══════════════════                                                       │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│   │    VPC      │  │   Subnets   │  │ VPC Endpoints│  │  KMS Key   │       │
│   │             │  │  (Private)  │  │    (6+)     │  │ (Optional) │       │
│   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│   ┌─────────────┐                                                          │
│   │ Shared ECR  │  acme-sagemaker-shared/base-*                           │
│   └─────────────┘                                                          │
│                                                                             │
│   用途级别 (按功能分):                                                      │
│   ═════════════════                                                         │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│   │  Studio SG  │  │ Training SG │  │Processing SG│  │ Inference SG│       │
│   │ (核心)      │  │ (工作负载)  │  │ (工作负载)  │  │ (工作负载)  │       │
│   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                                             │
│   项目级别 (按项目分):                                                      │
│   ═════════════════                                                         │
│   ┌────────────────────────────────────────────────────────────────┐       │
│   │ Project: rc-fraud-detection                                     │       │
│   │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────────┐│       │
│   │ │Execution    │ │ S3 Bucket   │ │ ECR Repo    │ │Model Group ││       │
│   │ │Role (已有)  │ │ (已有)      │ │ (可选)      │ │ (新增)     ││       │
│   │ └─────────────┘ └─────────────┘ └─────────────┘ └────────────┘│       │
│   └────────────────────────────────────────────────────────────────┘       │
│   ┌────────────────────────────────────────────────────────────────┐       │
│   │ Project: algo-recommendation                                    │       │
│   │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌────────────┐│       │
│   │ │Execution    │ │ S3 Bucket   │ │ ECR Repo    │ │Model Group ││       │
│   │ │Role (已有)  │ │ (已有)      │ │ (可选)      │ │ (新增)     ││       │
│   │ └─────────────┘ └─────────────┘ └─────────────┘ └────────────┘│       │
│   └────────────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. 检查清单

### 8.1 网络资源

- [ ] 创建 Training Jobs 安全组
- [ ] 创建 Processing Jobs 安全组
- [ ] 创建 Inference Endpoints 安全组
- [ ] 验证安全组规则

### 8.2 容器镜像（可选）

- [ ] 创建共享 ECR 仓库
- [ ] 创建项目级 ECR 仓库
- [ ] 配置 ECR Lifecycle Policy
- [ ] 推送基础镜像

### 8.3 模型治理

- [ ] 创建项目级 Model Package Group
- [ ] 配置 IAM 权限
- [ ] 测试模型注册流程

### 8.4 日志与监控

- [ ] 配置 CloudWatch 日志保留策略
- [ ] 创建关键指标告警
- [ ] 配置日志洞察查询

---

## 9. 下一步

- [15 - 工作负载实施指南](15-workload-implementation.md) - 详细实施步骤
- [10 - Processing 快速入门](10-sagemaker-processing.md) - 数据处理示例
- [12 - Training 快速入门](12-sagemaker-training.md) - 模型训练示例
- [13 - Inference 快速入门](13-realtime-inference.md) - 推理部署示例
