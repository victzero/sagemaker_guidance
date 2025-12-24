# 13 - SageMaker Real-Time Inference

> 本文档描述 SageMaker Real-Time Inference（实时推理）的设计与配置

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

## ⚠️ 设计范围声明

> **重要**：本设计主要覆盖 **开发/测试环境** 的实时推理部署。
>
> 生产级推理 Endpoint 需要额外考虑：
> - 独立 AWS 账号或 VPC 隔离
> - 高可用多 AZ 部署
> - 自动扩缩容策略
> - 生产级监控和告警
> - A/B 测试和蓝绿部署
>
> 详见 [01-架构概览](./01-architecture-overview.md) § 0 设计范围声明。

---

## 1. Real-Time Inference 概述

### 1.1 什么是 Real-Time Inference

SageMaker Real-Time Inference 提供托管的在线推理服务：

- **托管 Endpoint**：无需管理服务器
- **自动扩缩容**：根据负载自动调整
- **多模型部署**：单 Endpoint 多模型
- **A/B 测试**：流量分配

### 1.2 推理选项对比

| 类型                 | 延迟     | 适用场景           | 成本模式       |
| -------------------- | -------- | ------------------ | -------------- |
| **Real-Time**        | 毫秒级   | 在线预测           | 按实例时间     |
| **Serverless**       | 秒级     | 低流量/不定流量    | 按请求         |
| **Batch Transform**  | 分钟级   | 大批量离线预测     | 按 Job         |
| **Async Inference**  | 秒-分钟  | 大 Payload 异步    | 按实例时间     |

### 1.3 典型架构

```
客户端应用
    │
    │ HTTPS 请求
    ▼
SageMaker Endpoint
    │
    │ 负载均衡
    ▼
Endpoint Variant(s)
├── Production Variant (80% 流量)
└── Shadow Variant (20% 流量)
    │
    │ 模型推理
    ▼
返回预测结果
```

---

## 2. 权限设计

### 2.1 Inference 权限模型

```
部署者 (IAM User / Studio)
    │
    │ 创建 Model / Endpoint
    ▼
Endpoint
    │
    │ 使用 Execution Role
    ▼
Execution Role
├── 加载 S3 模型文件
├── 拉取 ECR 镜像
├── 写入 CloudWatch Logs
└── 写入 CloudWatch Metrics

调用者 (应用 / Lambda)
    │
    │ InvokeEndpoint
    ▼
Endpoint
```

### 2.2 Execution Role 追加权限

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "InferenceModelAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-{team}-{project}/models/*"
      ]
    },
    {
      "Sid": "InferenceContainerAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "*"
    },
    {
      "Sid": "InferenceLogging",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:{region}:{account-id}:log-group:/aws/sagemaker/Endpoints/*"
    }
  ]
}
```

### 2.3 Endpoint 管理权限

IAM User 创建/管理 Endpoint 的权限：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EndpointManagement",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateModel",
        "sagemaker:DescribeModel",
        "sagemaker:DeleteModel",
        "sagemaker:CreateEndpointConfig",
        "sagemaker:DescribeEndpointConfig",
        "sagemaker:DeleteEndpointConfig",
        "sagemaker:CreateEndpoint",
        "sagemaker:DescribeEndpoint",
        "sagemaker:DeleteEndpoint",
        "sagemaker:UpdateEndpoint",
        "sagemaker:InvokeEndpoint"
      ],
      "Resource": [
        "arn:aws:sagemaker:{region}:{account-id}:model/{team}-{project}-*",
        "arn:aws:sagemaker:{region}:{account-id}:endpoint-config/{team}-{project}-*",
        "arn:aws:sagemaker:{region}:{account-id}:endpoint/{team}-{project}-*"
      ]
    }
  ]
}
```

### 2.4 Endpoint 调用权限（应用侧）

```json
{
  "Sid": "AllowInvokeEndpoint",
  "Effect": "Allow",
  "Action": "sagemaker:InvokeEndpoint",
  "Resource": "arn:aws:sagemaker:{region}:{account-id}:endpoint/{team}-{project}-*"
}
```

---

## 3. 命名规范

### 3.1 资源命名

| 资源类型        | 命名模式                           | 示例                            |
| --------------- | ---------------------------------- | ------------------------------- |
| Model           | `{team}-{project}-{model}-v{n}`    | `rc-project-a-fraud-v1`         |
| EndpointConfig  | `{team}-{project}-{model}-config`  | `rc-project-a-fraud-config`     |
| Endpoint        | `{team}-{project}-{model}-ep`      | `rc-project-a-fraud-ep`         |

### 3.2 标签规范

| Tag Key     | Tag Value    | 说明         |
| ----------- | ------------ | ------------ |
| Team        | {team}       | 团队         |
| Project     | {project}    | 项目         |
| Model       | {model-name} | 模型名称     |
| Environment | dev/staging  | 环境         |
| Version     | v{n}         | 版本         |

---

## 4. 部署配置

### 4.1 基础部署流程

```python
from sagemaker.model import Model

# 1. 创建 Model
model = Model(
    image_uri='{account-id}.dkr.ecr.{region}.amazonaws.com/sagemaker-inference:latest',
    model_data='s3://{company}-sm-{team}-{project}/models/artifacts/{model-name}/model.tar.gz',
    role='arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole',
    name='{team}-{project}-{model}-v1',
    # VPC 配置（如需）
    vpc_config={
        'SecurityGroupIds': ['sg-sagemaker-studio'],
        'Subnets': ['{subnet-a}', '{subnet-b}']
    }
)

# 2. 部署 Endpoint
predictor = model.deploy(
    instance_type='ml.m5.xlarge',
    initial_instance_count=1,
    endpoint_name='{team}-{project}-{model}-ep',
    tags=[
        {'Key': 'Team', 'Value': '{team}'},
        {'Key': 'Project', 'Value': '{project}'},
        {'Key': 'Environment', 'Value': 'dev'}
    ]
)
```

### 4.2 PyTorch 模型部署

```python
from sagemaker.pytorch import PyTorchModel

model = PyTorchModel(
    model_data='s3://{company}-sm-{team}-{project}/models/artifacts/{model-name}/model.tar.gz',
    role='arn:aws:iam::{account-id}:role/SageMaker-{Team}-{Project}-ExecutionRole',
    entry_point='inference.py',
    framework_version='2.0.1',
    py_version='py310',
    name='{team}-{project}-pytorch-v1'
)

predictor = model.deploy(
    instance_type='ml.g4dn.xlarge',
    initial_instance_count=1,
    endpoint_name='{team}-{project}-pytorch-ep'
)
```

### 4.3 实例类型建议

| 模型类型       | 推荐实例          | 说明               |
| -------------- | ----------------- | ------------------ |
| 表格数据 ML    | ml.m5.large       | CPU 足够           |
| 树模型         | ml.m5.xlarge      | XGBoost/LightGBM   |
| 小型神经网络   | ml.g4dn.xlarge    | 单 GPU             |
| 大型神经网络   | ml.g4dn.2xlarge   | 更多 GPU 内存      |
| 低延迟要求     | ml.c5.xlarge      | CPU 优化           |

---

## 5. 调用 Endpoint

### 5.1 Python SDK 调用

```python
import boto3
import json

runtime = boto3.client('sagemaker-runtime')

response = runtime.invoke_endpoint(
    EndpointName='{team}-{project}-{model}-ep',
    ContentType='application/json',
    Body=json.dumps({
        'features': [1.0, 2.0, 3.0, 4.0]
    })
)

result = json.loads(response['Body'].read().decode())
print(result)
```

### 5.2 AWS CLI 调用

```bash
aws sagemaker-runtime invoke-endpoint \
  --endpoint-name {team}-{project}-{model}-ep \
  --content-type application/json \
  --body '{"features": [1.0, 2.0, 3.0, 4.0]}' \
  output.json

cat output.json
```

---

## 6. 自动扩缩容

### 6.1 配置 Auto Scaling

```python
import boto3

autoscaling = boto3.client('application-autoscaling')

# 注册可扩缩资源
autoscaling.register_scalable_target(
    ServiceNamespace='sagemaker',
    ResourceId='endpoint/{team}-{project}-{model}-ep/variant/AllTraffic',
    ScalableDimension='sagemaker:variant:DesiredInstanceCount',
    MinCapacity=1,
    MaxCapacity=4
)

# 配置扩缩策略
autoscaling.put_scaling_policy(
    PolicyName='{team}-{project}-scaling-policy',
    ServiceNamespace='sagemaker',
    ResourceId='endpoint/{team}-{project}-{model}-ep/variant/AllTraffic',
    ScalableDimension='sagemaker:variant:DesiredInstanceCount',
    PolicyType='TargetTrackingScaling',
    TargetTrackingScalingPolicyConfiguration={
        'TargetValue': 70.0,
        'PredefinedMetricSpecification': {
            'PredefinedMetricType': 'SageMakerVariantInvocationsPerInstance'
        },
        'ScaleInCooldown': 300,
        'ScaleOutCooldown': 60
    }
)
```

---

## 7. 成本控制

### 7.1 Serverless Inference（低流量场景）

```python
from sagemaker.serverless import ServerlessInferenceConfig

serverless_config = ServerlessInferenceConfig(
    memory_size_in_mb=2048,
    max_concurrency=5
)

predictor = model.deploy(
    serverless_inference_config=serverless_config,
    endpoint_name='{team}-{project}-{model}-serverless'
)
```

### 7.2 成本优化策略

| 策略                 | 说明                             |
| -------------------- | -------------------------------- |
| **Serverless**       | 低流量使用 Serverless Inference  |
| **合适的实例**       | 避免过度配置                     |
| **Auto Scaling**     | 根据负载自动调整                 |
| **开发环境清理**     | 不用时删除 dev Endpoint          |
| **Multi-Model**      | 多模型共享 Endpoint              |

### 7.3 开发环境自动清理

> ⚠️ 开发环境 Endpoint 应设置自动清理策略，避免闲置计费。

```bash
# 定期清理脚本（建议 cron 执行）
#!/bin/bash
# 删除超过 7 天未调用的 dev Endpoint

ENDPOINTS=$(aws sagemaker list-endpoints \
  --status-equals InService \
  --query 'Endpoints[?contains(EndpointName, `-dev-`)].EndpointName' \
  --output text)

for ep in $ENDPOINTS; do
  LAST_MODIFIED=$(aws sagemaker describe-endpoint \
    --endpoint-name $ep \
    --query 'LastModifiedTime' --output text)
  
  # 检查是否超过 7 天
  # ... 清理逻辑 ...
done
```

---

## 8. 监控与日志

### 8.1 CloudWatch 指标

| 指标                        | 说明           | 告警建议             |
| --------------------------- | -------------- | -------------------- |
| Invocations                 | 调用次数       | -                    |
| InvocationsPerInstance      | 每实例调用数   | 扩缩容依据           |
| ModelLatency                | 模型延迟       | > 1s 告警            |
| OverheadLatency             | 系统延迟       | > 200ms 告警         |
| Invocation4XXErrors         | 4XX 错误       | > 1% 告警            |
| Invocation5XXErrors         | 5XX 错误       | > 0.1% 告警          |
| CPUUtilization              | CPU 使用率     | > 80% 告警           |
| MemoryUtilization           | 内存使用率     | > 80% 告警           |

### 8.2 CloudWatch Logs

```
/aws/sagemaker/Endpoints/{endpoint-name}
```

---

## 9. CLI 命令

### 9.1 管理 Endpoint

```bash
# 列出 Endpoints
aws sagemaker list-endpoints

# 查看 Endpoint 详情
aws sagemaker describe-endpoint \
  --endpoint-name {team}-{project}-{model}-ep

# 删除 Endpoint
aws sagemaker delete-endpoint \
  --endpoint-name {team}-{project}-{model}-ep

# 删除 Endpoint Config
aws sagemaker delete-endpoint-config \
  --endpoint-config-name {team}-{project}-{model}-config

# 删除 Model
aws sagemaker delete-model \
  --model-name {team}-{project}-{model}-v1
```

---

## 10. 待完善内容

- [ ] Multi-Model Endpoint 配置
- [ ] A/B 测试配置
- [ ] 蓝绿部署配置
- [ ] 生产环境完整设计（独立文档）

---

## 11. 检查清单

### 部署前

- [ ] 模型文件已上传到 S3
- [ ] Execution Role 有推理权限
- [ ] 选择合适的实例类型
- [ ] 推理脚本已准备（如需要）

### 部署时

- [ ] 使用正确的命名规范
- [ ] 添加标签
- [ ] 配置 VPC（如需要）
- [ ] 设置 Auto Scaling（生产环境）

### 部署后

- [ ] 验证 Endpoint 状态为 InService
- [ ] 测试调用
- [ ] 配置监控告警
- [ ] （开发环境）设置清理策略

