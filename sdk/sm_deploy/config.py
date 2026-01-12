# =============================================================================
# config.py - 配置管理和自动发现
# =============================================================================
# 自动从环境变量、Tags、SageMaker Domain 获取 VPC/子网/安全组配置
# =============================================================================

import os
import boto3
import json
from dataclasses import dataclass, field
from typing import List, Optional
from functools import lru_cache


@dataclass
class DeployConfig:
    """部署配置类"""

    # 基础信息
    company: str
    team: str
    project: str
    region: str
    account_id: str

    # VPC 配置
    vpc_id: str
    subnet_ids: List[str]
    security_group_ids: List[str]

    # Role 配置
    inference_role_arn: str
    execution_role_arn: str

    # S3 配置
    bucket: str
    model_prefix: str = "models"
    output_prefix: str = "inference/output"

    # 可选配置
    tags: dict = field(default_factory=dict)

    def get_vpc_config(self) -> dict:
        """获取 VPC 配置（用于 CreateModel）"""
        return {
            "Subnets": self.subnet_ids,
            "SecurityGroupIds": self.security_group_ids,
        }

    def get_default_tags(self) -> List[dict]:
        """获取默认 Tags"""
        base_tags = [
            {"Key": "Team", "Value": self.team},
            {"Key": "Project", "Value": self.project},
            {"Key": "ManagedBy", "Value": f"{self.company}-sagemaker"},
        ]
        for k, v in self.tags.items():
            base_tags.append({"Key": k, "Value": v})
        return base_tags

    def get_model_name_prefix(self) -> str:
        """获取模型名称前缀（符合 IAM 策略限制）"""
        return f"{self.team}-{self.project}"

    def get_endpoint_name_prefix(self) -> str:
        """获取 Endpoint 名称前缀"""
        return f"{self.team}-{self.project}"


# =============================================================================
# 配置自动发现
# =============================================================================


def _get_env_or_raise(key: str) -> str:
    """获取环境变量，不存在则抛出异常"""
    value = os.environ.get(key)
    if not value:
        raise ValueError(f"Required environment variable '{key}' not set")
    return value


def _get_env_or_default(key: str, default: str) -> str:
    """获取环境变量，不存在则使用默认值"""
    return os.environ.get(key, default)


@lru_cache(maxsize=1)
def _get_account_id() -> str:
    """获取当前 AWS Account ID"""
    sts = boto3.client("sts")
    return sts.get_caller_identity()["Account"]


@lru_cache(maxsize=1)
def _get_region() -> str:
    """获取当前 AWS Region"""
    session = boto3.session.Session()
    return session.region_name or os.environ.get("AWS_REGION", "ap-northeast-1")


def _discover_from_domain() -> dict:
    """
    从 SageMaker Domain 发现 VPC 配置
    在 Studio 环境中运行时可自动获取
    """
    try:
        sm = boto3.client("sagemaker")

        # 尝试从环境变量获取 Domain ID
        domain_id = os.environ.get("DOMAIN_ID")

        if not domain_id:
            # 尝试列出 domains 并获取第一个
            response = sm.list_domains(MaxResults=1)
            if response.get("Domains"):
                domain_id = response["Domains"][0]["DomainId"]

        if not domain_id:
            return {}

        # 获取 Domain 详情
        domain = sm.describe_domain(DomainId=domain_id)

        vpc_id = domain.get("VpcId", "")
        subnet_ids = domain.get("SubnetIds", [])

        # 获取安全组（从 DefaultUserSettings）
        default_settings = domain.get("DefaultUserSettings", {})
        security_groups = default_settings.get("SecurityGroups", [])

        return {
            "vpc_id": vpc_id,
            "subnet_ids": subnet_ids,
            "security_group_ids": security_groups,
        }
    except Exception:
        return {}


def _discover_from_user_profile() -> dict:
    """
    从当前 User Profile 的 Tags 发现项目信息
    """
    try:
        # 在 Studio 环境中，这些环境变量通常可用
        user_profile_name = os.environ.get("USER_PROFILE_NAME", "")
        domain_id = os.environ.get("DOMAIN_ID", "")

        if not user_profile_name or not domain_id:
            return {}

        sm = boto3.client("sagemaker")
        profile = sm.describe_user_profile(
            DomainId=domain_id, UserProfileName=user_profile_name
        )

        # 从 Tags 获取 Team 和 Project
        tags = {t["Key"]: t["Value"] for t in profile.get("Tags", [])}

        return {
            "team": tags.get("Team", ""),
            "project": tags.get("Project", ""),
        }
    except Exception:
        return {}


def _format_name(name: str) -> str:
    """格式化名称：kebab-case -> PascalCase"""
    return "".join(word.capitalize() for word in name.replace("_", "-").split("-"))


@lru_cache(maxsize=1)
def get_config(
    company: Optional[str] = None,
    team: Optional[str] = None,
    project: Optional[str] = None,
) -> DeployConfig:
    """
    获取部署配置（自动发现 + 环境变量 + 参数覆盖）

    优先级: 参数 > 环境变量 > 自动发现

    Args:
        company: 公司名称（覆盖环境变量）
        team: 团队 ID（覆盖环境变量）
        project: 项目名称（覆盖环境变量）

    Returns:
        DeployConfig 实例

    Example:
        config = get_config()
        # 或指定参数
        config = get_config(team="rc", project="fraud-detection")
    """

    # 1. 自动发现
    domain_config = _discover_from_domain()
    profile_config = _discover_from_user_profile()

    # 2. 获取基础信息
    _company = company or _get_env_or_default("COMPANY", "acme")
    _team = team or profile_config.get("team") or _get_env_or_raise("TEAM")
    _project = project or profile_config.get("project") or _get_env_or_raise("PROJECT")
    _region = _get_region()
    _account_id = _get_account_id()

    # 3. 获取 VPC 配置
    _vpc_id = (
        os.environ.get("VPC_ID") or domain_config.get("vpc_id") or _get_env_or_raise("VPC_ID")
    )

    _subnet_ids = []
    if os.environ.get("PRIVATE_SUBNET_1_ID"):
        _subnet_ids.append(os.environ["PRIVATE_SUBNET_1_ID"])
    if os.environ.get("PRIVATE_SUBNET_2_ID"):
        _subnet_ids.append(os.environ["PRIVATE_SUBNET_2_ID"])
    if not _subnet_ids:
        _subnet_ids = domain_config.get("subnet_ids", [])
    if not _subnet_ids:
        raise ValueError("No subnet IDs found. Set PRIVATE_SUBNET_1_ID and PRIVATE_SUBNET_2_ID")

    _sg_ids = []
    if os.environ.get("SG_SAGEMAKER_STUDIO"):
        _sg_ids.append(os.environ["SG_SAGEMAKER_STUDIO"])
    if not _sg_ids:
        _sg_ids = domain_config.get("security_group_ids", [])
    if not _sg_ids:
        raise ValueError("No security group IDs found. Set SG_SAGEMAKER_STUDIO")

    # 4. 构建 Role ARN
    team_fullname = _get_env_or_default(f"TEAM_{_team.upper()}_FULLNAME", _team)
    team_formatted = _format_name(team_fullname)
    project_formatted = _format_name(_project)
    iam_path = _get_env_or_default("IAM_PATH", f"/{_company}-sagemaker/")

    # 去除 IAM_PATH 首尾的 /
    iam_path_clean = iam_path.strip("/")
    if iam_path_clean:
        iam_path_clean = f"{iam_path_clean}/"

    inference_role = f"SageMaker-{team_formatted}-{project_formatted}-InferenceRole"
    execution_role = f"SageMaker-{team_formatted}-{project_formatted}-ExecutionRole"

    inference_role_arn = f"arn:aws:iam::{_account_id}:role/{iam_path_clean}{inference_role}"
    execution_role_arn = f"arn:aws:iam::{_account_id}:role/{iam_path_clean}{execution_role}"

    # 5. S3 Bucket
    _bucket = _get_env_or_default("BUCKET", f"{_company}-sm-{_team}-{_project}")

    return DeployConfig(
        company=_company,
        team=_team,
        project=_project,
        region=_region,
        account_id=_account_id,
        vpc_id=_vpc_id,
        subnet_ids=_subnet_ids,
        security_group_ids=_sg_ids,
        inference_role_arn=inference_role_arn,
        execution_role_arn=execution_role_arn,
        bucket=_bucket,
    )


def print_config(config: DeployConfig = None):
    """打印当前配置（调试用）"""
    if config is None:
        config = get_config()

    print("=" * 60)
    print(" SageMaker Deploy Configuration")
    print("=" * 60)
    print(f"  Company:        {config.company}")
    print(f"  Team:           {config.team}")
    print(f"  Project:        {config.project}")
    print(f"  Region:         {config.region}")
    print(f"  Account ID:     {config.account_id}")
    print()
    print("  VPC Configuration:")
    print(f"    VPC ID:       {config.vpc_id}")
    print(f"    Subnets:      {config.subnet_ids}")
    print(f"    Security Groups: {config.security_group_ids}")
    print()
    print("  IAM Roles:")
    print(f"    Inference:    {config.inference_role_arn}")
    print(f"    Execution:    {config.execution_role_arn}")
    print()
    print(f"  S3 Bucket:      {config.bucket}")
    print("=" * 60)


