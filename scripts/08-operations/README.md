# 08-operations - 运维操作脚本

平台部署完成后的日常运维操作脚本。

> 📖 **详细文档**: [docs/16-operations.md](../../docs/16-operations.md)

---

## 架构设计

本模块复用 `scripts/lib/` 中的工厂函数，确保与初始部署脚本行为一致：

```
08-operations/
    ↓ 调用
scripts/lib/
├── discovery.sh         # 动态资源发现 (从 AWS 实时查询)
├── iam-core.sh          # IAM 创建 (复用 01-iam 模板)
├── s3-factory.sh        # S3 创建
└── sagemaker-factory.sh # Profile/Space 创建
```

**项目发现**：从 AWS IAM Groups 动态查询，新增项目后立即可见。

---

## 目录结构

```
08-operations/
├── 00-init.sh                        # 初始化脚本
├── user/                             # 用户管理
│   ├── add-user.sh                   # 新增用户到项目
│   ├── add-user-to-project.sh        # 已有用户加入新项目
│   ├── remove-user-from-project.sh   # 从项目移除用户
│   └── delete-user.sh                # 完全删除用户
├── project/                          # 项目管理
│   ├── add-project.sh                # 新增项目
│   └── delete-project.sh             # 删除项目
├── team/                             # 团队管理
│   ├── add-team.sh                   # 新增团队
│   └── delete-team.sh                # 删除团队
└── query/                            # 查询工具
    ├── list-users.sh                 # 列出用户
    └── list-projects.sh              # 列出项目
```

---

## 快速开始

```bash
cd scripts/08-operations

# 新增项目
./project/add-project.sh

# 新员工入职
./user/add-user.sh

# 跨项目协作
./user/add-user-to-project.sh

# 查询
./query/list-users.sh
./query/list-projects.sh
```

---

## 资源创建详情

### add-project.sh

| 资源类型     | 数量 | 说明                                       |
| ------------ | ---- | ------------------------------------------ |
| IAM Group    | 1    | `sagemaker-{team}-{project}`               |
| IAM Policies | 11   | 完整策略集，含 Deny 跨项目                 |
| IAM Roles    | 4    | Execution, Training, Processing, Inference |
| S3 Bucket    | 1    | 可选，标准目录结构                         |

### add-user.sh / add-user-to-project.sh

| 资源类型         | 说明                                  |
| ---------------- | ------------------------------------- |
| IAM User         | (仅 add-user) 带 Permissions Boundary |
| Group Membership | 加入团队组 + 项目组                   |
| User Profile     | 绑定项目 Execution Role               |
| Private Space    | 50GB EBS                              |

---

## 安全机制

- **所有操作**: 执行前显示资源清单，需确认
- **删除操作**: 需两次确认（输入资源名称）
- **权限隔离**: 新项目自动包含 Deny 跨项目策略
