# 16 - 运维操作指南

> **用途**：平台部署完成后的日常运维操作  
> **脚本位置**：`scripts/08-operations/`

---

## 📋 概览

平台部署完成后，日常运维需要处理用户、项目、团队的增删改操作。本模块提供交互式脚本，支持：

| 类别     | 场景                   | 脚本                               |
| -------- | ---------------------- | ---------------------------------- |
| 用户管理 | 新增用户到已有项目     | `user/add-user.sh`                 |
|          | 将已有用户添加到新项目 | `user/add-user-to-project.sh`      |
|          | 从项目移除用户         | `user/remove-user-from-project.sh` |
|          | 完全删除用户           | `user/delete-user.sh`              |
|          | **管理文件下载权限**   | `user/set-user-download-access.sh` |
| 项目管理 | 新增项目               | `project/add-project.sh`           |
|          | 删除项目               | `project/delete-project.sh`        |
| 团队管理 | 新增团队               | `team/add-team.sh`                 |
|          | 删除团队               | `team/delete-team.sh`              |
| 查询工具 | 列出用户               | `query/list-users.sh`              |
|          | 列出项目               | `query/list-projects.sh`           |

---

## 🔐 安全机制

### 执行前确认

所有脚本在执行前会：

1. **列出所有新增/变更的资源清单**
2. **等待用户确认** 后才执行

### 删除操作双重确认

高危操作（`delete-user.sh`、`delete-project.sh`、`delete-team.sh`）需要：

1. **第一次确认**：`确认删除? [y/N]`
2. **第二次确认**：输入资源名称才能执行

```
确认删除用户 'sm-rc-alice'? [y/N]: y

⚠️  最后确认！请输入用户名 'sm-rc-alice' 完成删除:
> sm-rc-alice
```

---

## 📂 目录结构

```
scripts/08-operations/
├── 00-init.sh                        # 初始化脚本
├── README.md                         # 详细文档
│
├── user/                             # 用户管理
│   ├── add-user.sh                   # 新增用户到项目
│   ├── add-user-to-project.sh        # 已有用户加入新项目
│   ├── remove-user-from-project.sh   # 从项目移除用户
│   ├── delete-user.sh                # 完全删除用户
│   └── set-user-download-access.sh   # 管理文件下载权限
│
├── project/                          # 项目管理
│   ├── add-project.sh                # 新增项目
│   └── delete-project.sh             # 删除项目
│
├── team/                             # 团队管理
│   ├── add-team.sh                   # 新增团队
│   └── delete-team.sh                # 删除团队
│
└── query/                            # 查询工具
    ├── list-users.sh                 # 列出用户
    └── list-projects.sh              # 列出项目
```

---

## 🚀 快速开始

### 新员工入职

```bash
cd scripts/08-operations
./user/add-user.sh
```

交互式选择团队、项目，输入用户名后自动创建：

- IAM User + Console 登录
- IAM Group 成员
- User Profile
- Private Space

### 用户跨项目协作

```bash
./user/add-user-to-project.sh
```

为已有用户创建新项目的访问权限。

### 新增项目

```bash
./project/add-project.sh
```

创建项目所需的完整 IAM 资源：

- IAM Group
- 3 个 IAM Policies
- 4 个 IAM Roles (Execution/Training/Processing/Inference)
- S3 Bucket (可选)

### 查询资源

```bash
# 列出所有用户
./query/list-users.sh

# 列出指定团队的用户
./query/list-users.sh --team rc

# 详细模式
./query/list-users.sh --detail
```

---

## 📊 场景详解

### 场景 1: 新增用户到项目

**触发条件**：新员工入职，需要加入已有项目

**涉及资源**：

| 资源类型      | 操作 | 数量 |
| ------------- | ---- | ---- |
| IAM User      | 创建 | 1    |
| IAM Group     | 加入 | 2    |
| User Profile  | 创建 | 1    |
| Private Space | 创建 | 1    |
| Console Login | 设置 | 1    |

### 场景 2: 将已有用户添加到新项目

**触发条件**：用户需要参与多个项目

**涉及资源**：

| 资源类型      | 操作 | 数量 |
| ------------- | ---- | ---- |
| IAM Group     | 加入 | 1    |
| User Profile  | 创建 | 1    |
| Private Space | 创建 | 1    |

### 场景 3: 从项目移除用户

**触发条件**：用户不再参与某项目

**涉及资源**：

| 资源类型      | 操作 | 数量 |
| ------------- | ---- | ---- |
| Private Space | 删除 | 1    |
| User Profile  | 删除 | 1    |
| IAM Group     | 移除 | 1    |

### 场景 4: 完全删除用户

**触发条件**：员工离职

**涉及资源**：

| 资源类型       | 操作 | 数量 |
| -------------- | ---- | ---- |
| Private Spaces | 删除 | 全部 |
| User Profiles  | 删除 | 全部 |
| IAM Groups     | 移除 | 全部 |
| IAM User       | 删除 | 1    |
| Access Keys    | 删除 | 全部 |
| MFA Devices    | 删除 | 全部 |

### 场景 5: 管理文件下载权限

**触发条件**：需要对特定用户（如特权用户）开启或关闭文件下载功能

**涉及资源**：

| 资源类型     | 操作     | 数量 |
| ------------ | -------- | ---- |
| User Profile | 更新 LCC | 1    |

**命令示例**：

```bash
# 允许用户下载 (开启白名单)
./user/set-user-download-access.sh profile-rc-fraud-alice enable

# 禁止用户下载 (关闭)
./user/set-user-download-access.sh profile-rc-fraud-alice disable

# 重置为全局默认 (跟随 Domain 配置)
./user/set-user-download-access.sh profile-rc-fraud-alice reset
```

**注意事项**：

- 修改后用户必须重启 JupyterLab Space 才能生效。
- Domain 全局默认配置由 `04-sagemaker-domain` 中的环境变量控制。

### 场景 6: 新增项目

**触发条件**：团队开始新项目

**涉及资源**：

| 资源类型     | 操作 | 数量 |
| ------------ | ---- | ---- |
| IAM Group    | 创建 | 1    |
| IAM Policies | 创建 | 3    |
| IAM Roles    | 创建 | 4    |
| S3 Bucket    | 创建 | 1    |

### 场景 7: 删除项目

**触发条件**：项目结束或合并

**涉及资源**：

| 资源类型       | 操作 | 数量 |
| -------------- | ---- | ---- |
| Private Spaces | 删除 | 全部 |
| User Profiles  | 删除 | 全部 |
| IAM Group      | 删除 | 1    |
| IAM Roles      | 删除 | 4    |
| IAM Policies   | 删除 | 3    |
| S3 Bucket      | 可选 | 1    |

### 场景 8: 新增团队

**触发条件**：组织扩展，新部门需要独立环境

**涉及资源**：

| 资源类型   | 操作 | 数量 |
| ---------- | ---- | ---- |
| IAM Group  | 创建 | 1    |
| IAM Policy | 创建 | 1    |

### 场景 9: 删除团队

**触发条件**：部门重组或撤销

**前提条件**：

- 团队下所有项目已删除
- 团队下所有用户已移除

---

## ⚙️ 配置说明

### 资源发现机制

运维脚本使用**动态发现**机制，直接从 AWS 实时查询资源状态，而非依赖静态配置文件：

| 资源类型 | 发现方式                       | 说明                                            |
| -------- | ------------------------------ | ----------------------------------------------- |
| 团队列表 | `discover_teams()`             | 从 IAM Groups 解析 `sagemaker-{team-fullname}`  |
| 项目列表 | `discover_projects_for_team()` | 从 IAM Groups 解析 `sagemaker-{team}-{project}` |
| 用户列表 | `discover_project_users()`     | 从 IAM Group 成员获取                           |

**优势**:

- 🔄 无需手动维护 `.env.shared` 中的 `TEAMS`/`*_PROJECTS` 变量
- ✅ 新增团队/项目后立即可见
- 🛡️ 基于真实环境状态操作，避免配置不一致

> **注意**: `.env.shared` 仍用于 `get_team_fullname()` 等映射函数，建议在新增团队后更新配置以便显示友好名称。

### 配置优先级

| 配置变量            | 来源                             | 用途                |
| ------------------- | -------------------------------- | ------------------- |
| `COMPANY`           | `.env.shared`                    | 公司前缀            |
| `TEAM_*_FULLNAME`   | `.env.shared`                    | 团队短 ID→ 全称映射 |
| `IAM_PATH`          | `01-iam/.env.local`              | IAM 资源路径        |
| `PASSWORD_PREFIX`   | `01-iam/.env.local`              | 初始密码前缀        |
| `PASSWORD_SUFFIX`   | `01-iam/.env.local`              | 初始密码后缀        |
| `DOMAIN_ID`         | `04-sagemaker-domain/.env.local` | SageMaker Domain    |
| `SPACE_EBS_SIZE_GB` | `05-user-profiles/.env.local`    | Private Space EBS   |

### 与初始化脚本的区别

| 脚本类型         | 资源发现方式       | 适用场景               |
| ---------------- | ------------------ | ---------------------- |
| **01-07 初始化** | `.env` 配置文件    | 声明式批量部署基础设施 |
| **08 运维脚本**  | 动态发现 (AWS API) | 交互式日常运维操作     |

---

## 🔗 相关文档

- [02 - IAM 权限设计](./02-iam-design.md) - IAM 资源命名规范
- [06 - User Profile 设计](./06-user-profile.md) - Profile 和 Space 设计
- [08 - 实施步骤](./08-implementation-guide.md) - 初始部署流程
