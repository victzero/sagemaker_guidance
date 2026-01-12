# =============================================================================
# endpoint.py - Endpoint 管理
# =============================================================================
# Endpoint 创建、更新、删除、调用
# =============================================================================

import boto3
import json
from datetime import datetime
from typing import Optional, List, Dict, Any, Union
from .config import get_config, DeployConfig


def create_endpoint_config(
    config_name: str,
    model_name: str,
    instance_type: str = "ml.t2.medium",
    instance_count: int = 1,
    config: DeployConfig = None,
    serverless: bool = False,
    serverless_memory_mb: int = 2048,
    serverless_max_concurrency: int = 5,
) -> str:
    """
    创建 EndpointConfig

    Args:
        config_name: 配置名称（不含项目前缀）
        model_name: 模型名称
        instance_type: 实例类型
        instance_count: 实例数量
        config: 部署配置
        serverless: 是否 Serverless
        serverless_memory_mb: Serverless 内存
        serverless_max_concurrency: Serverless 并发

    Returns:
        完整配置名称
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_endpoint_name_prefix()

    full_config_name = f"{prefix}-{config_name}"
    full_model_name = model_name if model_name.startswith(prefix) else f"{prefix}-{model_name}"

    if serverless:
        production_variants = [
            {
                "VariantName": "AllTraffic",
                "ModelName": full_model_name,
                "ServerlessConfig": {
                    "MemorySizeInMB": serverless_memory_mb,
                    "MaxConcurrency": serverless_max_concurrency,
                },
            }
        ]
    else:
        production_variants = [
            {
                "VariantName": "AllTraffic",
                "ModelName": full_model_name,
                "InstanceType": instance_type,
                "InitialInstanceCount": instance_count,
                "InitialVariantWeight": 1.0,
            }
        ]

    sm.create_endpoint_config(
        EndpointConfigName=full_config_name,
        ProductionVariants=production_variants,
        Tags=config.get_default_tags(),
    )

    print(f"✅ EndpointConfig created: {full_config_name}")
    return full_config_name


def create_endpoint(
    endpoint_name: str,
    endpoint_config_name: str,
    config: DeployConfig = None,
    wait: bool = True,
) -> str:
    """
    创建 Endpoint

    Args:
        endpoint_name: Endpoint 名称（不含项目前缀）
        endpoint_config_name: EndpointConfig 名称
        config: 部署配置
        wait: 是否等待 InService

    Returns:
        完整 Endpoint 名称
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_endpoint_name_prefix()

    full_endpoint_name = f"{prefix}-{endpoint_name}"
    full_config_name = (
        endpoint_config_name
        if endpoint_config_name.startswith(prefix)
        else f"{prefix}-{endpoint_config_name}"
    )

    sm.create_endpoint(
        EndpointName=full_endpoint_name,
        EndpointConfigName=full_config_name,
        Tags=config.get_default_tags(),
    )

    print(f"✅ Endpoint creating: {full_endpoint_name}")

    if wait:
        print("⏳ Waiting for endpoint to be InService...")
        waiter = sm.get_waiter("endpoint_in_service")
        waiter.wait(
            EndpointName=full_endpoint_name,
            WaiterConfig={"Delay": 30, "MaxAttempts": 60},
        )
        print(f"✅ Endpoint is InService: {full_endpoint_name}")

    return full_endpoint_name


def update_endpoint(
    endpoint_name: str,
    endpoint_config_name: str,
    config: DeployConfig = None,
    wait: bool = True,
) -> str:
    """
    更新 Endpoint（蓝绿部署）

    Args:
        endpoint_name: Endpoint 名称
        endpoint_config_name: 新的 EndpointConfig 名称
        config: 部署配置
        wait: 是否等待完成

    Returns:
        Endpoint 名称
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_endpoint_name_prefix()

    full_endpoint_name = (
        endpoint_name if endpoint_name.startswith(prefix) else f"{prefix}-{endpoint_name}"
    )
    full_config_name = (
        endpoint_config_name
        if endpoint_config_name.startswith(prefix)
        else f"{prefix}-{endpoint_config_name}"
    )

    sm.update_endpoint(
        EndpointName=full_endpoint_name,
        EndpointConfigName=full_config_name,
    )

    print(f"✅ Endpoint updating: {full_endpoint_name}")

    if wait:
        print("⏳ Waiting for endpoint update...")
        waiter = sm.get_waiter("endpoint_in_service")
        waiter.wait(
            EndpointName=full_endpoint_name,
            WaiterConfig={"Delay": 30, "MaxAttempts": 60},
        )
        print(f"✅ Endpoint updated: {full_endpoint_name}")

    return full_endpoint_name


def delete_endpoint(
    endpoint_name: str,
    delete_config: bool = True,
    delete_model: bool = False,
    config: DeployConfig = None,
) -> bool:
    """
    删除 Endpoint（及相关资源）

    Args:
        endpoint_name: Endpoint 名称
        delete_config: 是否同时删除 EndpointConfig
        delete_model: 是否同时删除 Model
        config: 部署配置

    Returns:
        是否成功
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_endpoint_name_prefix()

    full_endpoint_name = (
        endpoint_name if endpoint_name.startswith(prefix) else f"{prefix}-{endpoint_name}"
    )

    try:
        # 获取 Endpoint 详情
        endpoint_info = sm.describe_endpoint(EndpointName=full_endpoint_name)
        config_name = endpoint_info["EndpointConfigName"]

        # 删除 Endpoint
        sm.delete_endpoint(EndpointName=full_endpoint_name)
        print(f"✅ Endpoint deleted: {full_endpoint_name}")

        # 删除 EndpointConfig
        if delete_config:
            try:
                # 获取 Config 详情以获取 Model 名称
                config_info = sm.describe_endpoint_config(EndpointConfigName=config_name)
                model_names = [v["ModelName"] for v in config_info["ProductionVariants"]]

                sm.delete_endpoint_config(EndpointConfigName=config_name)
                print(f"✅ EndpointConfig deleted: {config_name}")

                # 删除 Model
                if delete_model:
                    for model_name in model_names:
                        try:
                            sm.delete_model(ModelName=model_name)
                            print(f"✅ Model deleted: {model_name}")
                        except Exception:
                            pass
            except Exception:
                pass

        return True

    except sm.exceptions.ClientError as e:
        if "Could not find endpoint" in str(e):
            print(f"⚠️  Endpoint not found: {full_endpoint_name}")
            return False
        raise


def invoke_endpoint(
    endpoint_name: str,
    data: Union[dict, list, str],
    content_type: str = "application/json",
    accept: str = "application/json",
    config: DeployConfig = None,
) -> Any:
    """
    调用 Endpoint 进行推理

    Args:
        endpoint_name: Endpoint 名称
        data: 输入数据
        content_type: 请求 Content-Type
        accept: 响应 Accept
        config: 部署配置

    Returns:
        推理结果

    Example:
        result = invoke_endpoint(
            endpoint_name="sklearn-v1",
            data={"instances": [[1.0, 2.0, 3.0]]}
        )
    """
    if config is None:
        config = get_config()

    runtime = boto3.client("sagemaker-runtime", region_name=config.region)
    prefix = config.get_endpoint_name_prefix()

    full_endpoint_name = (
        endpoint_name if endpoint_name.startswith(prefix) else f"{prefix}-{endpoint_name}"
    )

    # 序列化输入
    if isinstance(data, (dict, list)):
        body = json.dumps(data)
    else:
        body = data

    response = runtime.invoke_endpoint(
        EndpointName=full_endpoint_name,
        ContentType=content_type,
        Accept=accept,
        Body=body,
    )

    result = response["Body"].read().decode("utf-8")

    # 尝试解析 JSON
    if accept == "application/json":
        try:
            return json.loads(result)
        except json.JSONDecodeError:
            return result

    return result


def describe_endpoint(endpoint_name: str, config: DeployConfig = None) -> Dict[str, Any]:
    """
    获取 Endpoint 详情

    Args:
        endpoint_name: Endpoint 名称
        config: 部署配置

    Returns:
        Endpoint 详情
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_endpoint_name_prefix()

    full_endpoint_name = (
        endpoint_name if endpoint_name.startswith(prefix) else f"{prefix}-{endpoint_name}"
    )

    return sm.describe_endpoint(EndpointName=full_endpoint_name)


def list_endpoints(config: DeployConfig = None) -> List[Dict[str, Any]]:
    """
    列出项目的所有 Endpoints

    Args:
        config: 部署配置

    Returns:
        Endpoint 列表
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_endpoint_name_prefix()

    endpoints = []
    paginator = sm.get_paginator("list_endpoints")

    for page in paginator.paginate(NameContains=prefix, SortBy="CreationTime", SortOrder="Descending"):
        for ep in page["Endpoints"]:
            endpoints.append(
                {
                    "name": ep["EndpointName"],
                    "status": ep["EndpointStatus"],
                    "creation_time": ep["CreationTime"],
                    "last_modified": ep.get("LastModifiedTime"),
                }
            )

    return endpoints


