# sm_deploy - SageMaker 模型部署工具库

简化 SageMaker 模型部署流程，自动处理 VPC 配置，提供统一的部署接口。

## 特性

- 🔒 **VPC 自动注入**: 模型部署自动使用正确的 VPC/子网/安全组
- 🏷️ **命名规范**: 自动添加项目前缀，符合 IAM 策略要求
- 🔍 **配置发现**: 自动从环境变量、SageMaker Domain 发现配置
- 📦 **一键部署**: 简化 Model → EndpointConfig → Endpoint 流程

## 快速开始

### 1. 设置环境变量

在 Jupyter Notebook 中:

```python
import os

# 必需配置
os.environ["TEAM"] = "rc"
os.environ["PROJECT"] = "fraud-detection"

# VPC 配置（通常从 Domain 自动发现）
os.environ["VPC_ID"] = "vpc-xxx"
os.environ["PRIVATE_SUBNET_1_ID"] = "subnet-xxx"
os.environ["PRIVATE_SUBNET_2_ID"] = "subnet-yyy"
os.environ["SG_SAGEMAKER_STUDIO"] = "sg-xxx"
```

### 2. 部署模型

```python
import sys
sys.path.insert(0, "/path/to/sdk")

from sm_deploy import deploy_model

# 一键部署
endpoint = deploy_model(
    model_name="sklearn-v1",
    model_data_url="s3://bucket/models/model.tar.gz",
    image_uri="123456789.dkr.ecr.ap-northeast-1.amazonaws.com/sklearn:latest",
    instance_type="ml.m5.large"
)

# 或使用 Serverless
endpoint = deploy_model(
    model_name="sklearn-v1-serverless",
    model_data_url="s3://bucket/models/model.tar.gz",
    image_uri="123456789.dkr.ecr.ap-northeast-1.amazonaws.com/sklearn:latest",
    serverless=True,
    serverless_memory_mb=2048
)
```

### 3. 调用推理

```python
from sm_deploy import invoke_endpoint

result = invoke_endpoint(
    endpoint_name="sklearn-v1",
    data={"instances": [[1.0, 2.0, 3.0, 4.0, 5.0]]}
)
print(result)
```

### 4. 清理资源

```python
from sm_deploy import delete_endpoint

delete_endpoint("sklearn-v1", delete_config=True, delete_model=True)
```

## API 参考

### 配置管理

```python
from sm_deploy import get_config, print_config

# 获取配置
config = get_config()
print(config.subnet_ids)
print(config.inference_role_arn)

# 打印完整配置
print_config()
```

### 模型操作

```python
from sm_deploy import create_model, deploy_model, delete_model, list_models

# 仅创建 Model（不部署）
model_name = create_model(
    model_name="my-model",
    model_data_url="s3://...",
    image_uri="..."
)

# 一键部署
endpoint = deploy_model(...)

# 列出模型
models = list_models()

# 删除模型
delete_model("my-model")
```

### Endpoint 操作

```python
from sm_deploy import (
    create_endpoint_config,
    create_endpoint,
    update_endpoint,
    delete_endpoint,
    invoke_endpoint,
    list_endpoints,
)

# 分步创建
config_name = create_endpoint_config(
    config_name="my-config",
    model_name="my-model",
    instance_type="ml.m5.large"
)

endpoint_name = create_endpoint(
    endpoint_name="my-endpoint",
    endpoint_config_name=config_name
)

# 更新 Endpoint（蓝绿部署）
update_endpoint(
    endpoint_name="my-endpoint",
    endpoint_config_name="new-config"
)

# 调用
result = invoke_endpoint("my-endpoint", data={...})

# 列出
endpoints = list_endpoints()

# 删除（含清理）
delete_endpoint("my-endpoint", delete_config=True, delete_model=True)
```

### 批量推理

```python
from sm_deploy import create_batch_transform

job = create_batch_transform(
    job_name="batch-eval",
    model_name="sklearn-v1",
    input_s3_uri="s3://bucket/input/test.csv",
    instance_type="ml.m5.xlarge"
)
```

## 配置优先级

配置按以下优先级获取:

1. **函数参数** - 最高优先级
2. **环境变量** - `TEAM`, `PROJECT`, `VPC_ID` 等
3. **自动发现** - 从 SageMaker Domain/User Profile 获取

## 环境变量参考

| 变量 | 必需 | 说明 |
|------|------|------|
| `COMPANY` | 否 | 公司名称，默认 `acme` |
| `TEAM` | 是 | 团队 ID |
| `PROJECT` | 是 | 项目名称 |
| `VPC_ID` | 否 | VPC ID（可自动发现）|
| `PRIVATE_SUBNET_1_ID` | 否 | 私有子网 1（可自动发现）|
| `PRIVATE_SUBNET_2_ID` | 否 | 私有子网 2（可自动发现）|
| `SG_SAGEMAKER_STUDIO` | 否 | 安全组 ID（可自动发现）|
| `IAM_PATH` | 否 | IAM 路径，默认 `/{company}-sagemaker/` |
| `BUCKET` | 否 | S3 Bucket，默认 `{company}-sm-{team}-{project}` |

## 与 IAM 策略集成

本工具库自动:

1. **添加项目前缀**: 所有资源名称自动添加 `{team}-{project}-` 前缀
2. **注入 VPC 配置**: `CreateModel` 自动包含 VpcConfig
3. **使用正确角色**: 自动使用 `InferenceRole`

这确保所有操作符合 IAM 策略限制:

- ✅ 只能在指定 VPC/子网创建模型
- ✅ 只能管理本项目的资源
- ❌ 无法选择其他 VPC 或 Public Subnet


