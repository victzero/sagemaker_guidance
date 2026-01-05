# 06-ecr - ECR 容器镜像仓库

> Phase 2B: 为 SageMaker 工作负载创建 ECR 仓库

---

## 概述

本模块创建 Amazon ECR (Elastic Container Registry) 仓库，用于存储自定义 SageMaker 容器镜像。

### 是否需要 ECR？

| 场景 | 是否需要 |
|------|:--------:|
| 使用 AWS 内置算法/框架镜像 | ❌ |
| 使用 SageMaker 内置容器 (sklearn, pytorch, xgboost) | ❌ |
| 自定义预处理/推理代码 (Python 脚本) | ❌ |
| 自定义 Docker 镜像 (特殊依赖、私有包) | ✅ |
| 生产环境部署 (镜像版本管理) | ✅ 建议 |

---

## 创建的资源

### 共享仓库（默认启用）

| 仓库名称 | 用途 |
|----------|------|
| `{COMPANY}-sagemaker-shared/base-sklearn` | Scikit-learn 基础镜像 |
| `{COMPANY}-sagemaker-shared/base-pytorch` | PyTorch 基础镜像 |
| `{COMPANY}-sagemaker-shared/base-xgboost` | XGBoost 基础镜像 |

### 项目仓库（可选）

设置 `ECR_CREATE_PROJECT_REPOS=true` 后创建：

| 仓库名称 | 用途 |
|----------|------|
| `{COMPANY}-sm-{team}-{project}/preprocessing` | 数据预处理镜像 |
| `{COMPANY}-sm-{team}-{project}/training` | 训练镜像 |
| `{COMPANY}-sm-{team}-{project}/inference` | 推理镜像 |

---

## 配置

在 `.env.shared` 中配置：

```bash
# ECR 配置
ENABLE_ECR=true                                        # 是否启用 ECR 模块
ECR_SHARED_REPOS="base-sklearn base-pytorch base-xgboost"  # 共享仓库类型
ECR_PROJECT_REPOS="preprocessing training inference"   # 项目仓库类型
ECR_CREATE_PROJECT_REPOS=false                         # 是否创建项目级仓库
ECR_IMAGE_RETENTION=10                                 # 保留最近 N 个镜像
```

---

## 使用方法

### 快速设置

```bash
cd scripts/06-ecr
./setup-all.sh
```

### 分步执行

```bash
# 1. 创建仓库
./01-create-repositories.sh

# 2. 验证
./verify.sh
```

---

## 镜像使用

### 1. 登录 ECR

```bash
aws ecr get-login-password --region ap-northeast-1 | \
    docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.ap-northeast-1.amazonaws.com
```

### 2. 构建并推送镜像

```bash
# 构建
docker build -t my-processor:latest .

# 标记
docker tag my-processor:latest \
    123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/acme-sagemaker-shared/base-sklearn:latest

# 推送
docker push \
    123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/acme-sagemaker-shared/base-sklearn:latest
```

### 3. 在 SageMaker 中使用

```python
from sagemaker.processing import Processor

# ECR 镜像 URI
image_uri = "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/acme-sagemaker-shared/base-sklearn:latest"

processor = Processor(
    role=execution_role,
    image_uri=image_uri,
    instance_count=1,
    instance_type="ml.m5.xlarge",
)
```

---

## Lifecycle Policy

每个仓库自动配置生命周期策略：

- **保留规则**: 保留最近 N 个镜像（默认 10）
- **过期规则**: 超过保留数量的镜像自动删除

修改保留数量：

```bash
# 在 .env.shared 中设置
ECR_IMAGE_RETENTION=20
```

---

## 清理

```bash
# ⚠️ 会删除所有仓库和镜像
./cleanup.sh
```

---

## 文件结构

```
06-ecr/
├── 00-init.sh                 # 初始化脚本
├── 01-create-repositories.sh  # 创建仓库
├── setup-all.sh               # 一键设置
├── verify.sh                  # 验证脚本
├── cleanup.sh                 # 清理脚本
├── README.md                  # 本文档
└── output/
    └── repositories.env       # 仓库信息
```

---

## 权限要求

执行此脚本需要以下 IAM 权限：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:CreateRepository",
                "ecr:DeleteRepository",
                "ecr:DescribeRepositories",
                "ecr:PutLifecyclePolicy",
                "ecr:GetLifecyclePolicy",
                "ecr:DescribeImages",
                "ecr:GetAuthorizationToken",
                "ecr:TagResource"
            ],
            "Resource": "*"
        }
    ]
}
```

---

## 下一步

1. **构建基础镜像** (可选): 创建团队共用的基础容器镜像
2. **继续 Phase 2C**: 创建 Model Registry (`07-model-registry`)

