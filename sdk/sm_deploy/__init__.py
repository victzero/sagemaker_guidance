# =============================================================================
# sm_deploy - SageMaker 模型部署工具库
# =============================================================================
# 简化模型部署流程，自动处理 VPC 配置，提供统一的部署接口
#
# 使用方法:
#   from sm_deploy import deploy_model, create_endpoint
#
# =============================================================================

from .config import DeployConfig, get_config
from .model import create_model, deploy_model
from .endpoint import (
    create_endpoint_config,
    create_endpoint,
    update_endpoint,
    delete_endpoint,
    invoke_endpoint,
    list_endpoints,
)
from .batch import create_batch_transform

__version__ = "1.0.0"

__all__ = [
    # Config
    "DeployConfig",
    "get_config",
    # Model
    "create_model",
    "deploy_model",
    # Endpoint
    "create_endpoint_config",
    "create_endpoint",
    "update_endpoint",
    "delete_endpoint",
    "invoke_endpoint",
    "list_endpoints",
    # Batch
    "create_batch_transform",
]


