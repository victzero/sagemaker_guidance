# Notebooks - SageMaker 模型部署模板

提供模型部署的最佳实践 Notebook 模板。

## 模板列表

| Notebook | 说明 |
|----------|------|
| [01-model-deployment.ipynb](01-model-deployment.ipynb) | 模型部署入门（Real-Time / Serverless） |

## 使用方法

### 方式 1: 从 S3 复制

```bash
# 在 SageMaker Studio 终端中执行
aws s3 cp s3://{company}-sm-shared-assets/templates/notebooks/ ./notebooks/ --recursive
aws s3 cp s3://{company}-sm-shared-assets/templates/sdk/ ./sdk/ --recursive
```

### 方式 2: Clone 仓库

```bash
git clone <repo-url>
cd sagemaker_guidance
```

### 方式 3: 直接下载

从 GitHub 下载 `notebooks/` 和 `sdk/` 目录到您的工作空间。

## 依赖

这些 Notebook 依赖 `sdk/sm_deploy` 工具库：

```python
import sys
sys.path.insert(0, './sdk')

from sm_deploy import deploy_model
```

## 配置要求

运行前需设置以下环境变量：

```python
import os
os.environ["TEAM"] = "your-team-id"
os.environ["PROJECT"] = "your-project-name"
```

VPC 配置通常可从 SageMaker Domain 自动发现，如果失败请手动设置。


