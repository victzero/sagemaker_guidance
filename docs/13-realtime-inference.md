# 13 - SageMaker Real-Time Inference

> 模型部署与实时推理快速入门

---

## 快速开始

> ✅ **前提条件**：已完成 Phase 1 基础设施部署，已训练好模型

### 环境准备

在 SageMaker Studio JupyterLab 中运行：

```python
import sagemaker
import boto3
from sagemaker.model import Model
from sagemaker.predictor import Predictor

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
# Inference Endpoint 使用 InferenceRole
ROLE_NAME = f"SageMaker-{TEAM_FULLNAME}-{PROJECT_CAMEL}-InferenceRole"
ROLE_ARN = f"arn:aws:iam::{account_id}:role/{COMPANY}-sagemaker/{ROLE_NAME}"
BUCKET = f"{COMPANY}-sm-{TEAM}-{PROJECT}"

print(f"Region: {region}")
print(f"Inference Role ARN: {ROLE_ARN}")
```

---

## ⚠️ 设计范围声明

> **重要**：本指南主要覆盖 **开发/测试环境** 的实时推理部署。
>
> 生产级推理 Endpoint 需要额外考虑：
> - 高可用多 AZ 部署
> - 自动扩缩容策略
> - 生产级监控和告警
> - A/B 测试和蓝绿部署

---

## 1. 推理选项概述

### 1.1 推理类型对比

| 类型 | 延迟 | 适用场景 | 成本模式 |
|------|------|----------|----------|
| **Real-Time** | 毫秒级 | 在线服务、API | 按实例小时计费 |
| **Serverless** | 秒级 | 低流量、间歇性 | 按请求计费 |
| **Batch** | 分钟~小时 | 离线批量预测 | 按处理时间 |
| **Async** | 秒~分钟 | 长时间推理 | 按处理时间 |

### 1.2 POC 推荐方案

| 场景 | 推荐方案 | 说明 |
|------|----------|------|
| 快速验证 | **Serverless Endpoint** | 零运维、按需付费 |
| 性能测试 | Real-Time Endpoint | 稳定延迟 |
| 批量评估 | Batch Transform | 成本最低 |

---

## 2. 方案一：Serverless Endpoint（推荐 POC）

### 2.1 为什么选择 Serverless

- ✅ **无需管理实例**：按请求自动扩缩容
- ✅ **成本优化**：只为实际使用付费
- ✅ **快速部署**：几分钟内可用
- ⚠️ **冷启动延迟**：首次请求可能需要几秒

### 2.2 部署 Serverless Endpoint

```python
from sagemaker.serverless import ServerlessInferenceConfig
from sagemaker.sklearn import SKLearnModel

# 假设已有训练好的模型
MODEL_DATA = f's3://{BUCKET}/training/output/{TEAM}-{PROJECT}-sklearn-xxxx/output/model.tar.gz'

# 创建 SKLearn 模型
sklearn_model = SKLearnModel(
    model_data=MODEL_DATA,
    role=ROLE_ARN,
    entry_point='inference.py',  # 推理脚本
    framework_version='1.2-1',
    py_version='py3',
    sagemaker_session=session
)

# Serverless 配置
serverless_config = ServerlessInferenceConfig(
    memory_size_in_mb=2048,  # 1024, 2048, 3072, 4096, 5120, 6144
    max_concurrency=5        # 最大并发数
)

# 部署 Serverless Endpoint
predictor = sklearn_model.deploy(
    serverless_inference_config=serverless_config,
    endpoint_name=f'{TEAM}-{PROJECT}-serverless',
    tags=[
        {'Key': 'Team', 'Value': TEAM},
        {'Key': 'Project', 'Value': PROJECT},
        {'Key': 'Environment', 'Value': 'dev'}
    ]
)

print(f"Endpoint deployed: {predictor.endpoint_name}")
```

### 2.3 推理脚本示例

创建 `inference.py`：

```python
# inference.py - SKLearn 推理脚本
import os
import joblib
import numpy as np

def model_fn(model_dir):
    """加载模型"""
    model_path = os.path.join(model_dir, 'model.joblib')
    model = joblib.load(model_path)
    return model

def input_fn(request_body, request_content_type):
    """解析输入数据"""
    if request_content_type == 'application/json':
        import json
        data = json.loads(request_body)
        return np.array(data['instances'])
    else:
        raise ValueError(f"Unsupported content type: {request_content_type}")

def predict_fn(input_data, model):
    """执行预测"""
    predictions = model.predict(input_data)
    probabilities = model.predict_proba(input_data)
    return {
        'predictions': predictions.tolist(),
        'probabilities': probabilities.tolist()
    }

def output_fn(prediction, accept):
    """格式化输出"""
    import json
    return json.dumps(prediction), 'application/json'
```

---

## 3. 方案二：Real-Time Endpoint

### 3.1 部署 Real-Time Endpoint

```python
from sagemaker.sklearn import SKLearnModel

# 创建模型
sklearn_model = SKLearnModel(
    model_data=MODEL_DATA,
    role=ROLE_ARN,
    entry_point='inference.py',
    framework_version='1.2-1',
    py_version='py3',
    sagemaker_session=session
)

# 部署 Real-Time Endpoint
predictor = sklearn_model.deploy(
    initial_instance_count=1,
    instance_type='ml.t2.medium',  # 开发测试用小实例
    endpoint_name=f'{TEAM}-{PROJECT}-realtime',
    tags=[
        {'Key': 'Team', 'Value': TEAM},
        {'Key': 'Project', 'Value': PROJECT}
    ]
)

print(f"Endpoint deployed: {predictor.endpoint_name}")
```

### 3.2 实例类型选择

| 场景 | 推荐实例 | 配置 | 参考价格 |
|------|----------|------|----------|
| 开发测试 | ml.t2.medium | 2 vCPU, 4 GB | ~$0.056/h |
| 轻量生产 | ml.m5.large | 2 vCPU, 8 GB | ~$0.134/h |
| 高性能 | ml.m5.xlarge | 4 vCPU, 16 GB | ~$0.269/h |
| GPU 推理 | ml.g4dn.xlarge | 1x T4 | ~$0.736/h |

---

## 4. 调用 Endpoint

### 4.1 使用 SageMaker SDK

```python
import json
from sagemaker.serializers import JSONSerializer
from sagemaker.deserializers import JSONDeserializer

# 配置序列化器
predictor.serializer = JSONSerializer()
predictor.deserializer = JSONDeserializer()

# 准备测试数据
test_data = {
    'instances': [
        [0.5, 1.2, 0.3, 0.8, 0.1],
        [-0.2, 0.7, 1.1, 0.4, 0.6]
    ]
}

# 调用 Endpoint
response = predictor.predict(test_data)
print(f"Predictions: {response['predictions']}")
print(f"Probabilities: {response['probabilities']}")
```

### 4.2 使用 Boto3

```python
import boto3
import json

runtime = boto3.client('sagemaker-runtime')

# 调用 Endpoint
response = runtime.invoke_endpoint(
    EndpointName=f'{TEAM}-{PROJECT}-serverless',
    ContentType='application/json',
    Body=json.dumps({
        'instances': [[0.5, 1.2, 0.3, 0.8, 0.1]]
    })
)

result = json.loads(response['Body'].read().decode())
print(f"Result: {result}")
```

### 4.3 使用 curl（外部调用）

```bash
# 需要 AWS 签名，推荐使用 awscurl
pip install awscurl

awscurl --service sagemaker \
  --region ap-northeast-1 \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"instances": [[0.5, 1.2, 0.3]]}' \
  https://runtime.sagemaker.ap-northeast-1.amazonaws.com/endpoints/{endpoint-name}/invocations
```

---

## 5. 方案三：Batch Transform

### 5.1 适用场景

- 大量数据批量预测
- 不需要实时响应
- 成本敏感场景

### 5.2 执行 Batch Transform

```python
from sagemaker.sklearn import SKLearnModel

# 创建模型
sklearn_model = SKLearnModel(
    model_data=MODEL_DATA,
    role=ROLE_ARN,
    framework_version='1.2-1',
    py_version='py3',
    sagemaker_session=session
)

# 创建 Transformer
transformer = sklearn_model.transformer(
    instance_count=1,
    instance_type='ml.m5.xlarge',
    output_path=f's3://{BUCKET}/batch-output/',
    strategy='MultiRecord',
    assemble_with='Line',
    accept='text/csv'
)

# 执行批量推理
transformer.transform(
    data=f's3://{BUCKET}/batch-input/test.csv',
    content_type='text/csv',
    split_type='Line'
)

# 等待完成
transformer.wait()
print(f"Output: {transformer.output_path}")
```

---

## 6. 清理资源

### 6.1 删除 Endpoint

```python
# 使用 SDK
predictor.delete_endpoint()

# 或使用 boto3
sm_client = boto3.client('sagemaker')
sm_client.delete_endpoint(EndpointName=f'{TEAM}-{PROJECT}-serverless')
sm_client.delete_endpoint_config(EndpointConfigName=f'{TEAM}-{PROJECT}-serverless')
```

### 6.2 CLI 命令

```bash
# 删除 Endpoint
aws sagemaker delete-endpoint --endpoint-name {endpoint-name}

# 删除 Endpoint Config
aws sagemaker delete-endpoint-config --endpoint-config-name {config-name}

# 删除 Model
aws sagemaker delete-model --model-name {model-name}
```

---

## 7. 成本控制

### 7.1 POC 阶段建议

| 建议 | 说明 |
|------|------|
| 使用 Serverless | 按需付费，无闲置成本 |
| 用完即删 | 测试完立即删除 Endpoint |
| 小实例 | 开发测试用 ml.t2.medium |

### 7.2 Serverless 成本估算

| 内存 | 价格 | 1000 次请求成本 |
|------|------|-----------------|
| 1024 MB | $0.0000200/ms | ~$2-4 |
| 2048 MB | $0.0000400/ms | ~$4-8 |
| 4096 MB | $0.0000800/ms | ~$8-16 |

---

## 8. 监控与日志

### 8.1 CloudWatch Metrics

| 指标 | 说明 | 告警建议 |
|------|------|----------|
| Invocations | 调用次数 | - |
| ModelLatency | 模型延迟 | > 1s |
| InvocationErrors | 调用错误 | > 0 |
| MemoryUtilization | 内存使用率 | > 80% |

### 8.2 CloudWatch Logs

```
/aws/sagemaker/Endpoints/{endpoint-name}
```

---

## 9. CLI 快速参考

```bash
# 列出 Endpoints
aws sagemaker list-endpoints

# 查看 Endpoint 详情
aws sagemaker describe-endpoint --endpoint-name {endpoint-name}

# 列出 Models
aws sagemaker list-models

# 删除 Endpoint
aws sagemaker delete-endpoint --endpoint-name {endpoint-name}
```

---

## 10. 故障排查

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `ModelError` | 推理脚本错误 | 检查 CloudWatch Logs |
| `ValidationError` | 输入格式错误 | 检查 Content-Type |
| 冷启动慢 | Serverless 特性 | 使用预置并发或 Real-Time |
| 内存不足 | 模型太大 | 增加 memory_size_in_mb |

### 调试推理脚本

```python
# 本地测试
from inference import model_fn, input_fn, predict_fn

# 加载模型
model = model_fn('/path/to/model')

# 模拟输入
import json
test_input = json.dumps({'instances': [[0.5, 1.2, 0.3]]})
data = input_fn(test_input, 'application/json')

# 预测
result = predict_fn(data, model)
print(result)
```

---

## 11. 检查清单

### ✅ 部署前

- [ ] 模型产物已保存到 S3
- [ ] 推理脚本已准备
- [ ] 选择合适的 Endpoint 类型

### ✅ 部署后

- [ ] 测试 Endpoint 可用
- [ ] 验证预测结果正确
- [ ] 配置监控告警

### ✅ 使用完毕

- [ ] **删除 Endpoint**（避免持续计费）
- [ ] 清理不需要的 Model
- [ ] 记录部署配置

---

## 下一步

- [10 - SageMaker Processing](10-sagemaker-processing.md) - 数据处理
- [12 - SageMaker Training](12-sagemaker-training.md) - 模型训练
- [USER-GUIDE](USER-GUIDE.md) - 用户使用手册
