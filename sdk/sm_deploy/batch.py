# =============================================================================
# batch.py - 批量推理 (Batch Transform)
# =============================================================================
# 批量推理作业创建和管理
# =============================================================================

import boto3
from datetime import datetime
from typing import Optional, List, Dict, Any
from .config import get_config, DeployConfig


def create_batch_transform(
    job_name: str,
    model_name: str,
    input_s3_uri: str,
    output_s3_uri: str = None,
    instance_type: str = "ml.m5.large",
    instance_count: int = 1,
    config: DeployConfig = None,
    content_type: str = "text/csv",
    split_type: str = "Line",
    strategy: str = "MultiRecord",
    max_payload_mb: int = 6,
    wait: bool = True,
) -> str:
    """
    创建批量推理作业

    Args:
        job_name: 作业名称（不含项目前缀）
        model_name: 模型名称
        input_s3_uri: 输入数据 S3 路径
        output_s3_uri: 输出 S3 路径（默认自动生成）
        instance_type: 实例类型
        instance_count: 实例数量
        config: 部署配置
        content_type: 输入数据类型
        split_type: 分割方式 (Line, RecordIO, None)
        strategy: 处理策略 (SingleRecord, MultiRecord)
        max_payload_mb: 最大 payload 大小 (MB)
        wait: 是否等待完成

    Returns:
        Transform Job 名称

    Example:
        job = create_batch_transform(
            job_name="batch-20240101",
            model_name="sklearn-v1",
            input_s3_uri="s3://bucket/input/data.csv"
        )
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_model_name_prefix()

    # 生成完整名称
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    full_job_name = f"{prefix}-{job_name}-{timestamp}"
    full_model_name = model_name if model_name.startswith(prefix) else f"{prefix}-{model_name}"

    # 默认输出路径
    if output_s3_uri is None:
        output_s3_uri = f"s3://{config.bucket}/batch-transform/{job_name}/{timestamp}/"

    # 创建 Transform Job
    sm.create_transform_job(
        TransformJobName=full_job_name,
        ModelName=full_model_name,
        TransformInput={
            "DataSource": {
                "S3DataSource": {
                    "S3DataType": "S3Prefix",
                    "S3Uri": input_s3_uri,
                }
            },
            "ContentType": content_type,
            "SplitType": split_type,
        },
        TransformOutput={
            "S3OutputPath": output_s3_uri,
            "AssembleWith": "Line",
        },
        TransformResources={
            "InstanceType": instance_type,
            "InstanceCount": instance_count,
        },
        BatchStrategy=strategy,
        MaxPayloadInMB=max_payload_mb,
        Tags=config.get_default_tags(),
    )

    print(f"✅ Transform job created: {full_job_name}")
    print(f"   Input:  {input_s3_uri}")
    print(f"   Output: {output_s3_uri}")

    if wait:
        print("⏳ Waiting for transform job to complete...")
        waiter = sm.get_waiter("transform_job_completed_or_stopped")
        waiter.wait(
            TransformJobName=full_job_name,
            WaiterConfig={"Delay": 30, "MaxAttempts": 120},
        )

        # 检查最终状态
        job_info = sm.describe_transform_job(TransformJobName=full_job_name)
        status = job_info["TransformJobStatus"]

        if status == "Completed":
            print(f"✅ Transform job completed: {full_job_name}")
            print(f"   Output: {output_s3_uri}")
        else:
            print(f"❌ Transform job failed: {status}")
            if "FailureReason" in job_info:
                print(f"   Reason: {job_info['FailureReason']}")

    return full_job_name


def describe_transform_job(job_name: str, config: DeployConfig = None) -> Dict[str, Any]:
    """
    获取 Transform Job 详情

    Args:
        job_name: 作业名称
        config: 部署配置

    Returns:
        作业详情
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)

    return sm.describe_transform_job(TransformJobName=job_name)


def stop_transform_job(job_name: str, config: DeployConfig = None) -> bool:
    """
    停止 Transform Job

    Args:
        job_name: 作业名称
        config: 部署配置

    Returns:
        是否成功
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)

    try:
        sm.stop_transform_job(TransformJobName=job_name)
        print(f"✅ Transform job stopped: {job_name}")
        return True
    except Exception as e:
        print(f"❌ Failed to stop job: {e}")
        return False


def list_transform_jobs(config: DeployConfig = None, max_results: int = 20) -> List[Dict[str, Any]]:
    """
    列出项目的 Transform Jobs

    Args:
        config: 部署配置
        max_results: 最大返回数量

    Returns:
        作业列表
    """
    if config is None:
        config = get_config()

    sm = boto3.client("sagemaker", region_name=config.region)
    prefix = config.get_model_name_prefix()

    response = sm.list_transform_jobs(
        NameContains=prefix,
        SortBy="CreationTime",
        SortOrder="Descending",
        MaxResults=max_results,
    )

    jobs = []
    for job in response.get("TransformJobSummaries", []):
        jobs.append(
            {
                "name": job["TransformJobName"],
                "status": job["TransformJobStatus"],
                "creation_time": job["CreationTime"],
                "end_time": job.get("TransformEndTime"),
            }
        )

    return jobs


