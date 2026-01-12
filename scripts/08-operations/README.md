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

### 动态发现 vs 静态配置

| 脚本类型         | 资源发现方式       | 适用场景               |
| ---------------- | ------------------ | ---------------------- |
| **01-07 初始化** | `.env` 配置文件    | 声明式批量部署基础设施 |
| **08 运维脚本**  | 动态发现 (AWS API) | 交互式日常运维操作     |

**运维脚本特性**:

- 🔄 团队/项目列表从 IAM Groups 实时查询 (`discover_teams()`, `discover_projects_for_team()`)
- ✅ 新增资源后立即可见，无需更新配置
- 🛡️ 基于真实环境状态操作，避免配置不一致

> **注意**: `.env.shared` 仍用于 `get_team_fullname()` 映射函数，建议新增团队后更新配置以便显示友好名称。

---

## 目录结构

```
08-operations/
├── 00-init.sh                        # 初始化脚本
├── user/                             # 用户管理
│   ├── add-user.sh                   # 新增用户到项目
│   ├── add-user-to-project.sh        # 已有用户加入新项目
│   ├── remove-user-from-project.sh   # 从项目移除用户
│   ├── delete-user.sh                # 完全删除用户
│   └── set-user-download-access.sh   # 管理文件下载权限
├── project/                          # 项目管理
│   ├── add-project.sh                # 新增项目
│   ├── delete-project.sh             # 删除项目
│   └── set-instance-whitelist.sh     # 管理实例类型白名单
├── team/                             # 团队管理
│   ├── add-team.sh                   # 新增团队
│   └── delete-team.sh                # 删除团队
└── query/                            # 查询工具
    ├── list-users.sh                 # 列出用户
    ├── list-projects.sh              # 列出项目
    └── list-instance-whitelists.sh   # 列出实例类型白名单
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

# 实例类型白名单管理
./project/set-instance-whitelist.sh rc fraud preset gpu     # 升级到 GPU
./project/set-instance-whitelist.sh rc fraud preset default # 降级回默认
./project/set-instance-whitelist.sh rc fraud show           # 查看配置

# 查询
./query/list-users.sh
./query/list-projects.sh
./query/list-instance-whitelists.sh
```

---

## 资源创建详情

### add-project.sh

| 资源类型     | 数量 | 说明                                           |
| ------------ | ---- | ---------------------------------------------- |
| IAM Group    | 1    | `sagemaker-{team}-{project}`                   |
| IAM Policies | 12   | 完整策略集，含 DenyCrossProject 跨项目资源隔离 |
| IAM Roles    | 4    | Execution, Training, Processing, Inference     |
| S3 Bucket    | 1    | 可选，标准目录结构                             |

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
- **成本控制**: 实例类型白名单限制高成本机器启动

---

## 实例类型白名单

限制用户在 SageMaker Studio 中可选择的实例类型，防止启动高成本机器。

### 预设类型

| 预设名             | 允许的实例类型               | 适用场景                   |
| ------------------ | ---------------------------- | -------------------------- |
| `default`          | ml.t3.\*, ml.m5.large/xlarge | 日常开发、小型实验         |
| `gpu`              | 上述 + ml.g4dn._, ml.g5._    | 深度学习训练               |
| `large_memory`     | 上述 + ml.r5.\*              | 大数据处理                 |
| `high_performance` | 上述 + ml.c5._, ml.p3._      | 高性能计算                 |
| `unrestricted`     | 全部                         | 特殊项目（不创建限制策略） |

### 配置层级

1. **初始化配置** (`.env.shared`): 项目创建时自动应用
2. **运维变更** (`set-instance-whitelist.sh`): 运行时动态调整

### 常用操作

```bash
# 查看所有项目白名单状态
./query/list-instance-whitelists.sh

# 查看单个项目详情
./project/set-instance-whitelist.sh rc fraud show

# 升级到 GPU 预设（临时开放）
./project/set-instance-whitelist.sh rc fraud preset gpu

# 降级回默认预设
./project/set-instance-whitelist.sh rc fraud preset default

# 移除限制（不推荐）
./project/set-instance-whitelist.sh rc fraud preset unrestricted

# 自定义实例类型（必须包含 system）
./project/set-instance-whitelist.sh rc fraud custom "ml.t3.medium,ml.p3.2xlarge,system"

# 重置为初始配置
./project/set-instance-whitelist.sh rc fraud reset
```

### 注意事项

- 所有预设必须包含 `system`，否则 JupyterLab 无法启动
- 配置立即生效，但已运行的 Space 不受影响
- 用户下次启动 Space 时应用新限制
