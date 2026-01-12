# 19 - 模型部署最佳实践

> 使用 sm_deploy 工具库简化模型部署，自动处理 VPC 配置

---

## 概述

本指南介绍如何使用项目提供的 `sm_deploy` 工具库进行模型部署，主要解决以下问题：

| 问题 | 解决方案 |
|------|---------|
| VPC/子网选择繁琐 | 自动从 Domain 发现或环境变量注入 |
| 误选 Public Subnet | IAM 策略强制限制 + SDK 自动注入 |
| 命名不规范 | 自动添加项目前缀，符合 IAM 策略 |
| 部署流程复杂 | 一键部署函数，封装 Model → Config → Endpoint |

---

## 架构设计

### 安全边界

```
┌─────────────────────────────────────────────────────────────────┐
│  IAM 策略层                                                      │
│  InferenceRole-Ops 策略:                                         │
│    ✅ CreateModel 必须指定 VpcConfig                             │
│    ✅ VpcSubnets 只能是指定私有子网                               │
│    ✅ VpcSecurityGroupIds 只能是 SageMaker SG                    │
│    ❌ 未指定 VPC → 拒绝                                          │
│    ❌ 使用其他子网 → 拒绝                                         │
├─────────────────────────────────────────────────────────────────┤
│  SDK 工具层 (sm_deploy)                                          │
│    • 自动发现 VPC/子网/安全组配置                                  │
│    • 自动注入 VpcConfig 到 CreateModel                           │
│    • 自动添加项目前缀到资源名称                                    │
│    • 封装部署流程，简化 API                                       │
├─────────────────────────────────────────────────────────────────┤
│  用户层 (Jupyter Notebook)                                       │
│    • 只需指定模型路径、实例类型                                    │
│    • 无需关心 VPC 配置                                            │
│    • 无需了解 IAM 策略限制                                        │
└─────────────────────────────────────────────────────────────────┘
```

### VPC 限制策略

IAM 策略 `inference-role-ops.json.tpl` 包含以下限制：

```json
{
  "Sid": "AllowCreateModelWithVpcRestriction",
  "Effect": "Allow",
  "Action": ["sagemaker:CreateModel"],
  "Resource": ["arn:aws:sagemaker:*:*:model/${TEAM}-${PROJECT}-*"],
  "Condition": {
    "ForAllValues:StringEquals": {
      "sagemaker:VpcSubnets": ["${PRIVATE_SUBNET_1_ID}", "${PRIVATE_SUBNET_2_ID}"],
      "sagemaker:VpcSecurityGroupIds": ["${SG_SAGEMAKER_STUDIO}"]
    },
    "Null": {
      "sagemaker:VpcSubnets": "false"
    }
  }
}
```

**效果**：
- ❌ 不指定 VPC → API 拒绝
- ❌ 使用非指定子网 → API 拒绝
- ❌ 使用非指定安全组 → API 拒绝
- ✅ 使用正确的 VPC 配置 → 允许

---

## SDK 工具库

### 目录结构

```
sdk/sm_deploy/
├── __init__.py      # 导出主要函数
├── config.py        # 配置管理和自动发现
├── model.py         # 模型创建和部署
├── endpoint.py      # Endpoint 管理
├── batch.py         # 批量推理
└── README.md        # 使用文档
```

### 核心功能

| 函数 | 说明 |
|------|------|
| `get_config()` | 获取部署配置（自动发现）|
| `deploy_model()` | 一键部署模型到 Endpoint |
| `create_model()` | 仅创建 Model（不部署）|
| `invoke_endpoint()` | 调用 Endpoint 推理 |
| `delete_endpoint()` | 删除 Endpoint 及相关资源 |
| `create_batch_transform()` | 创建批量推理作业 |

### 配置自动发现

SDK 按以下优先级获取配置：

1. **函数参数** - 最高优先级
2. **环境变量** - `TEAM`, `PROJECT`, `VPC_ID` 等
3. **SageMaker Domain** - 自动从 Domain 获取 VPC 配置
4. **User Profile Tags** - 从 Tags 获取 Team/Project

```python
from sm_deploy import get_config

# 自动发现配置
config = get_config()

# 或手动指定
config = get_config(team="rc", project="fraud-detection")
```

---

## 快速开始

### 1. 设置环境

```python
import os
os.environ["TEAM"] = "rc"
os.environ["PROJECT"] = "fraud-detection"
os.environ["TEAM_RC_FULLNAME"] = "RiskControl"
```

### 2. 检查配置

```python
from sm_deploy.config import print_config

print_config()
```

### 3. 部署模型

```python
from sm_deploy import deploy_model

endpoint = deploy_model(
    model_name="sklearn-v1",
    model_data_url="s3://bucket/models/model.tar.gz",
    image_uri="123456789.dkr.ecr.region.amazonaws.com/sklearn:latest",
    instance_type="ml.m5.large"
)
```

### 4. 调用推理

```python
from sm_deploy import invoke_endpoint

result = invoke_endpoint(
    endpoint_name="sklearn-v1",
    data={"instances": [[1.0, 2.0, 3.0]]}
)
```

### 5. 清理资源

```python
from sm_deploy import delete_endpoint

delete_endpoint("sklearn-v1", delete_config=True, delete_model=True)
```

---

## Notebook 模板

项目提供以下 Notebook 模板：

| 模板 | 说明 |
|------|------|
| `01-model-deployment.ipynb` | 模型部署入门 |

### 获取模板

**方式 1: 从 S3 下载**

```bash
aws s3 cp s3://{company}-sm-shared-assets/templates/sdk/ ./sdk/ --recursive
aws s3 cp s3://{company}-sm-shared-assets/templates/notebooks/ ./notebooks/ --recursive
```

**方式 2: Clone 仓库**

```bash
git clone <repo-url>
cp -r sagemaker_guidance/sdk ./
cp -r sagemaker_guidance/notebooks ./
```

---

## 部署方式对比

| 方式 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| **Real-Time** | 在线服务 | 低延迟 | 持续计费 |
| **Serverless** | 低流量、测试 | 按需付费 | 冷启动 |
| **Batch Transform** | 批量预测 | 成本低 | 非实时 |

### 推荐方案

| 阶段 | 推荐 |
|------|------|
| 开发测试 | Serverless 或 ml.t2.medium |
| 性能验证 | Real-Time ml.m5.large |
| 生产部署 | Real-Time + AutoScaling |
| 批量评估 | Batch Transform |

---

## 成本控制

### 开发阶段建议

1. **优先使用 Serverless** - 按请求付费，无闲置成本
2. **用完即删** - 测试完立即删除 Endpoint
3. **使用小实例** - 开发用 ml.t2.medium

### 实例成本参考

| 实例类型 | 配置 | 参考价格 |
|----------|------|----------|
| ml.t2.medium | 2 vCPU, 4 GB | ~$0.056/h |
| ml.m5.large | 2 vCPU, 8 GB | ~$0.134/h |
| ml.m5.xlarge | 4 vCPU, 16 GB | ~$0.269/h |
| ml.g4dn.xlarge | 1x T4 GPU | ~$0.736/h |

---

## 故障排查

### 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|---------|
| `AccessDenied: CreateModel` | VPC 配置不符合策略 | 检查 subnet/SG 是否正确 |
| `ValidationException: VpcConfig` | 未指定 VPC | 使用 SDK 自动注入 |
| `ResourceNotFound: Role` | Role ARN 错误 | 检查 TEAM_*_FULLNAME 映射 |

### 调试步骤

1. 检查配置：`print_config()`
2. 验证 VPC：`config.get_vpc_config()`
3. 检查 Role：`config.inference_role_arn`

---

## 管理员指南

### 同步模板到 S3

```bash
cd scripts/09-templates
./sync-templates.sh
```

### 更新 IAM 策略

VPC 限制在 `scripts/01-iam/policies/inference-role-ops.json.tpl` 中配置：

- `${PRIVATE_SUBNET_1_ID}` - 允许的子网 1
- `${PRIVATE_SUBNET_2_ID}` - 允许的子网 2
- `${SG_SAGEMAKER_STUDIO}` - 允许的安全组

更新后需重新部署 IAM 策略。

---

## 相关文档

- [02 - IAM 权限设计](02-iam-design.md) - IAM 策略详解
- [03 - VPC 网络设计](03-vpc-network.md) - VPC 配置
- [13 - Real-Time Inference](13-realtime-inference.md) - 推理详细文档


