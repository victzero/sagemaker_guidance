# 06-ecr - ECR 容器镜像仓库

为 SageMaker 工作负载创建 ECR 仓库。

> 📖 **详细文档**: [docs/17-ecr.md](../../docs/17-ecr.md)

---

## 快速开始

```bash
cd scripts/06-ecr
./setup-all.sh
```

## 文件结构

```
06-ecr/
├── 00-init.sh                 # 初始化脚本
├── 01-create-repositories.sh  # 创建仓库
├── setup-all.sh               # 一键设置
├── verify.sh                  # 验证脚本
├── cleanup.sh                 # 清理脚本
└── output/
    └── repositories.env       # 仓库信息
```

## 配置

在 `.env.shared` 中配置：

```bash
ENABLE_ECR=true
ECR_SHARED_REPOS="base-sklearn base-pytorch base-xgboost"
ECR_PROJECT_REPOS="preprocessing training inference"
ECR_CREATE_PROJECT_REPOS=false
ECR_IMAGE_RETENTION=10
```

## 清理

```bash
# ⚠️ 会删除所有仓库和镜像
./cleanup.sh
```
