# 07-model-registry - SageMaker Model Registry

为每个项目创建 Model Package Group，实现模型版本管理。

> 📖 **详细文档**: [docs/18-model-registry.md](../../docs/18-model-registry.md)

---

## 快速开始

```bash
cd scripts/07-model-registry
./setup-all.sh
```

## 文件结构

```
07-model-registry/
├── 00-init.sh                  # 初始化脚本
├── 01-create-model-groups.sh   # 创建 Model Package Groups
├── setup-all.sh                # 一键设置
├── verify.sh                   # 验证脚本
├── cleanup.sh                  # 清理脚本
└── output/
    └── model-groups.env        # Group 列表
```

## 配置

在 `.env.shared` 中配置：

```bash
ENABLE_MODEL_REGISTRY=true
```

Model Package Groups 根据 `TEAMS` 和 `{TEAM}_PROJECTS` 自动创建。

## 清理

```bash
# ⚠️ 会删除所有 Model Package Groups 和模型版本
./cleanup.sh
```
