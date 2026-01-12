# SDK - SageMaker 工具库

为数据科学家提供的 Python 工具库，简化 SageMaker 操作。

## 目录结构

```
sdk/
└── sm_deploy/          # 模型部署工具库
    ├── __init__.py
    ├── config.py       # 配置管理
    ├── model.py        # 模型操作
    ├── endpoint.py     # Endpoint 管理
    ├── batch.py        # 批量推理
    └── README.md       # 详细文档
```

## 快速使用

```python
import sys
sys.path.insert(0, '/path/to/sdk')

from sm_deploy import deploy_model, invoke_endpoint

# 部署模型
endpoint = deploy_model(
    model_name="my-model",
    model_data_url="s3://bucket/model.tar.gz",
    image_uri="123456789.dkr.ecr.region.amazonaws.com/image:tag",
    instance_type="ml.m5.large"
)

# 推理
result = invoke_endpoint("my-model", {"instances": [[1, 2, 3]]})
```

## 详细文档

- [sm_deploy 使用文档](sm_deploy/README.md)
- [模型部署最佳实践](../docs/19-deployment-guide.md)


