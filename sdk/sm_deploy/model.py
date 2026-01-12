# =============================================================================
# model.py - 模型创建和部署
# =============================================================================
# 封装 SageMaker Model 创建，自动注入 VPC 配置
# =============================================================================

import boto3
from datetime import datetime
from typing import Optional, List, Dict, Any
from .config import get_config, DeployConfig


def create_model(
    model_name: str,
    model_data_url: str,
    image_uri: str,
    config: DeployConfig = None,
    environment: Dict[str, str] = None,
    enable_network_isolation: bool = False,
) -> str:
    """
    创建 SageMaker Model（自动注入 VPC 配置）

    Args:
        model_name: 模型名称（不含项目前缀，会自动添加）
        model_data_url: S3 模型文件路径 (s3://bucket/path/model.tar.gz)
        image_uri: Docker 镜像 URI
        config: 部署配置（默认自动获取）
        environment: 容器环境变量
        enable_network_isolation: 是否启用网络隔离

    Returns:
        完整的模型名称

    Example:
        model_name = create_model(
            model_name="sklearn-v1",
            model_data_url="s3://my-bucket/models/model.tar.gz",
            image_uri="123456789.dkr.ecr.region.amazonaws.com/sklearn:latest"
        )
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)

    # 自动添加项目前缀（符合 IAM 策略要求）
    full_model_name = f"{config.get_model_name_prefix()}-{model_name}"

    # 构建 Model 参数
    create_params = {
        "ModelName": full_model_name,
        "PrimaryContainer": {
            "Image": image_uri,
            "ModelDataUrl": model_data_url,
            "Environment": environment or {},
        },
        "ExecutionRoleArn": config.inference_role_arn,
        "Tags": config.get_default_tags(),
        # 强制 VPC 配置（IAM 策略要求）
        "VpcConfig": config.get_vpc_config(),
        "EnableNetworkIsolation": enable_network_isolation,
    }

    try:
        response = sm.create_model(**create_params)
        print(f"✅ Model created: {full_model_name}")
        print(f"   ARN: {response['ModelArn']}")
        return full_model_name
    except sm.exceptions.ClientError as e:
        if "already exists" in str(e):
            print(f"⚠️  Model already exists: {full_model_name}")
            return full_model_name
        raise


def deploy_model(
    model_name: str,
    model_data_url: str,
    image_uri: str,
    instance_type: str = "ml.t2.medium",
    instance_count: int = 1,
    config: DeployConfig = None,
    environment: Dict[str, str] = None,
    serverless: bool = False,
    serverless_memory_mb: int = 2048,
    serverless_max_concurrency: int = 5,
    wait: bool = True,
) -> str:
    """
    一键部署模型到 Endpoint

    Args:
        model_name: 模型名称（不含项目前缀）
        model_data_url: S3 模型文件路径
        image_uri: Docker 镜像 URI
        instance_type: 实例类型（Real-Time 模式）
        instance_count: 实例数量
        config: 部署配置
        environment: 容器环境变量
        serverless: 是否使用 Serverless 模式
        serverless_memory_mb: Serverless 内存大小
        serverless_max_concurrency: Serverless 最大并发
        wait: 是否等待部署完成

    Returns:
        Endpoint 名称

    Example:
        # Real-Time Endpoint
        endpoint = deploy_model(
            model_name="sklearn-v1",
            model_data_url="s3://bucket/model.tar.gz",
            image_uri="123456789.dkr.ecr.region.amazonaws.com/sklearn:latest",
            instance_type="ml.m5.large"
        )

        # Serverless Endpoint
        endpoint = deploy_model(
            model_name="sklearn-v1",
            model_data_url="s3://bucket/model.tar.gz",
            image_uri="123456789.dkr.ecr.region.amazonaws.com/sklearn:latest",
            serverless=True
        )
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)

    # 1. 创建 Model
    full_model_name = create_model(
        model_name=model_name,
        model_data_url=model_data_url,
        image_uri=image_uri,
        config=config,
        environment=environment,
    )

    # 2. 创建 EndpointConfig
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    endpoint_config_name = f"{full_model_name}-config-{timestamp}"
    endpoint_name = f"{full_model_name}"

    if serverless:
        # Serverless 配置
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
        # Real-Time 配置
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
        EndpointConfigName=endpoint_config_name,
        ProductionVariants=production_variants,
        Tags=config.get_default_tags(),
    )
    print(f"✅ EndpointConfig created: {endpoint_config_name}")

    # 3. 创建或更新 Endpoint
    try:
        sm.create_endpoint(
            EndpointName=endpoint_name,
            EndpointConfigName=endpoint_config_name,
            Tags=config.get_default_tags(),
        )
        print(f"✅ Endpoint creating: {endpoint_name}")
    except sm.exceptions.ClientError as e:
        if "Cannot create already existing" in str(e):
            print(f"⚠️  Endpoint exists, updating: {endpoint_name}")
            sm.update_endpoint(
                EndpointName=endpoint_name,
                EndpointConfigName=endpoint_config_name,
            )

    # 4. 等待部署完成
    if wait:
        print("⏳ Waiting for endpoint to be InService...")
        waiter = sm.get_waiter("endpoint_in_service")
        waiter.wait(
            EndpointName=endpoint_name,
            WaiterConfig={"Delay": 30, "MaxAttempts": 60},
        )
        print(f"✅ Endpoint is InService: {endpoint_name}")

    return endpoint_name


def delete_model(model_name: str, config: DeployConfig = None) -> bool:
    """
    删除 SageMaker Model

    Args:
        model_name: 模型名称（完整名称或短名称）
        config: 部署配置

    Returns:
        是否成功删除
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)

    # 如果没有项目前缀，添加它
    prefix = config.get_model_name_prefix()
    if not model_name.startswith(prefix):
        model_name = f"{prefix}-{model_name}"

    try:
        sm.delete_model(ModelName=model_name)
        print(f"✅ Model deleted: {model_name}")
        return True
    except sm.exceptions.ClientError as e:
        if "Could not find model" in str(e):
            print(f"⚠️  Model not found: {model_name}")
            return False
        raise


def list_models(config: DeployConfig = None) -> List[Dict[str, Any]]:
    """
    列出项目的所有模型

    Args:
        config: 部署配置

    Returns:
        模型列表
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_model_name_prefix()

    models = []
    paginator = sm.get_paginator("list_models")

    for page in paginator.paginate(NameContains=prefix, SortBy="CreationTime", SortOrder="Descending"):
        for model in page["Models"]:
            models.append(
                {
                    "name": model["ModelName"],
                    "arn": model["ModelArn"],
                    "creation_time": model["CreationTime"],
                }
            )

    return models


