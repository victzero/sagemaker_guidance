# scripts/lib - 共享函数库

供多个模块复用的核心函数库。

## 设计原则

1. **01-07 模块是权威实现** - lib 中的函数从 01-iam 等模块提取
2. **不重复实现** - lib 复用 01-iam/policies 中的模板
3. **01-07 行为不变** - lib 只是将核心函数提取出来供复用

---

## 文件说明

| 文件                   | 说明                                             |
| ---------------------- | ------------------------------------------------ |
| `iam-core.sh`          | IAM 核心函数（模板渲染、策略/角色/组 创建/删除） |
| `discovery.sh`         | 动态资源发现（从 AWS 实时查询团队/项目/用户）    |
| `s3-factory.sh`        | S3 Bucket 创建/删除函数                          |
| `sagemaker-factory.sh` | User Profile、Space 创建/删除函数                |

---

## 核心函数一览

### discovery.sh

**设计目标**: 08-operations 运维脚本使用动态发现，而非依赖静态 `.env` 配置。

| 函数                                      | 说明                              |
| ----------------------------------------- | --------------------------------- |
| `discover_teams`                          | 从 IAM Groups 发现所有团队短 ID   |
| `discover_projects_for_team <team>`       | 发现团队下的所有项目              |
| `get_project_list_dynamic <team>`         | 动态发现 + fallback 到 `.env`     |
| `project_exists <team> <project>`         | 检查项目是否存在 (通过 IAM Group) |
| `check_project_roles <team> <project>`    | 检查项目 IAM Roles 是否完整       |
| `check_project_bucket <team> <project>`   | 检查项目 S3 Bucket 是否存在       |
| `discover_project_users <team> <project>` | 获取项目的用户列表                |
| `discover_user_projects <iam_username>`   | 获取用户参与的项目列表            |

**发现机制**:

```
IAM Groups 命名规范 → 反向解析资源
├── sagemaker-{team-fullname}         → 团队
├── sagemaker-{team}-{project}        → 项目
└── Group 成员                        → 用户
```

**与初始化脚本的区别**:

| 脚本类型     | 资源发现    | 说明           |
| ------------ | ----------- | -------------- |
| 01-07 初始化 | `.env` 配置 | 声明式批量部署 |
| 08 运维脚本  | 动态发现    | 交互式日常操作 |

### iam-core.sh

**Group 创建函数:**
| 函数 | 说明 |
|------|------|
| `create_iam_group <group_name>` | 创建 IAM Group (通用) |
| `create_team_group <team>` | 创建团队 Group |
| `create_project_group <team> <project>` | 创建项目 Group |

**User 创建函数:**
| 函数 | 说明 |
|------|------|
| `create_iam_user <username> <team> [enable_console] [project]` | 创建 IAM User (含 Boundary, 可选 Project tag) |
| `create_admin_user <admin_name> [enable_console]` | 创建管理员用户 |
| `add_user_to_group <username> <group_name>` | 添加用户到 Group (幂等, 已存在则跳过) |

**一站式创建函数:**
| 函数 | 说明 |
|------|------|
| `create_team_iam <team>` | 一站式创建团队 IAM (Group + Policy + 绑定) |
| `create_project_iam <team> <project>` | 一站式创建项目 IAM (Group + Policies + Roles + 绑定) |

**策略绑定函数:**
| 函数 | 说明 |
|------|------|
| `attach_policy_to_group <group_name> <policy_arn>` | 绑定单个策略到 Group (幂等，已绑定则跳过) |
| `bind_team_policies <team>` | 绑定团队策略到 Group (4 个策略) |
| `bind_policies_to_project_group <team> <project>` | 绑定项目策略到 Group (4 个策略) |

**删除函数:**
| 函数 | 说明 |
|------|------|
| `delete_team_iam <team>` | 一站式删除团队 IAM |
| `delete_project_iam <team> <project>` | 一站式删除项目 IAM |
| `delete_iam_group <group_name>` | 删除 Group (含策略分离) |
| `delete_iam_role <role_name>` | 删除 Role (含策略分离) |
| `delete_iam_policy <policy_arn>` | 删除 Policy (含版本清理) |
| `delete_iam_user <username>` | 删除 User (含关联清理) |
| `remove_user_from_groups <username>` | 移除用户的所有组关系 |

### sagemaker-factory.sh

**资源发现函数:**
| 函数 | 说明 |
|------|------|
| `get_domain_id` | 获取 Domain ID (带缓存) |
| `get_studio_security_group` | 获取 Studio Security Group ID |
| `get_studio_sg` | `get_studio_security_group` 的别名 |
| `get_project_short <project>` | 获取项目短名 (fraud-detection → fraud) |

**创建函数:**
| 函数 | 说明 |
|------|------|
| `create_user_profile_and_space <...>` | 一站式创建 Profile + Space |
| `create_user_profile <domain_id> <profile_name> <role_arn> <sg_id> <team> <project> <username>` | 创建 User Profile |
| `create_private_space <domain_id> <space_name> <profile_name> <team> <project> <username> [ebs_gb]` | 创建 Private Space |

**删除函数:**
| 函数 | 说明 |
|------|------|
| `delete_user_sagemaker_resources <domain_id> <profile> <space>` | 一站式删除用户 SageMaker 资源 |
| `delete_sagemaker_user_profile <domain_id> <profile_name>` | 删除 User Profile (含 Apps 清理) |
| `delete_private_space <domain_id> <space_name>` | 删除 Space (含 Apps 清理) |

### s3-factory.sh

**创建函数:**
| 函数 | 说明 |
|------|------|
| `create_s3_bucket <bucket> <team> <project> [options]` | 通用 Bucket 创建 (含加密、Tags) |
| `create_directory_structure <bucket> [--shared]` | 创建目录结构 (项目/共享) |
| `create_project_bucket <team> <project>` | 创建项目 Bucket (简化接口) |
| `create_shared_bucket` | 创建共享 Bucket |
| `create_project_s3 <team> <project> [--with-lifecycle]` | 一站式创建项目 S3 资源 |

**配置函数:**
| 函数 | 说明 |
|------|------|
| `configure_bucket_policy <team> <project>` | 配置 Bucket 访问策略 |
| `configure_bucket_lifecycle <team> <project>` | 配置生命周期规则 |

**删除函数:**
| 函数 | 说明 |
|------|------|
| `delete_project_bucket <team> <project>` | 删除项目 S3 Bucket |
| `delete_bucket <bucket_name>` | 删除 Bucket (含清空) |
| `empty_bucket <bucket_name>` | 清空 Bucket |

---

## 使用方式

```bash
# 在脚本中加载 (需先设置 POLICY_TEMPLATES_DIR)
POLICY_TEMPLATES_DIR="${SCRIPTS_ROOT}/01-iam/policies"
source "${SCRIPTS_ROOT}/lib/iam-core.sh"
source "${SCRIPTS_ROOT}/lib/discovery.sh"
source "${SCRIPTS_ROOT}/lib/s3-factory.sh"
source "${SCRIPTS_ROOT}/lib/sagemaker-factory.sh"

# 创建团队
create_team_iam "ds"

# 创建项目
create_project_iam "ds" "fraud-detection"
create_project_s3 "ds" "fraud-detection" --with-lifecycle

# 删除项目
delete_project_iam "ds" "fraud-detection"
delete_project_bucket "ds" "fraud-detection"
```

---

## Tags 标准

所有 IAM 资源使用统一的 Tag 规范：

| Tag Key     | 值                              | 说明                                   |
| ----------- | ------------------------------- | -------------------------------------- |
| `ManagedBy` | `${COMPANY}-sagemaker`          | 统一标识，用于资源筛选和清理           |
| `Company`   | `${COMPANY}`                    | 公司标识                               |
| `Team`      | `${team_fullname}`              | 团队全称 (如 `data-science`)，人类可读 |
| `Project`   | `${project}`                    | 项目名称 (如 `fraud-detection`)        |
| `Owner`     | `${username}`                   | 资源拥有者 (用于 Users)                |
| `Purpose`   | `Training/Processing/Inference` | Role 用途 (仅 Role)                    |

**示例:**

```bash
# User Tags
Key=Team,Value=data-science
Key=Project,Value=fraud-detection
Key=ManagedBy,Value=acme-sagemaker
Key=Company,Value=acme
Key=Owner,Value=sm-ds-alice

# Role Tags
Key=Team,Value=data-science
Key=Project,Value=fraud-detection
Key=Purpose,Value=Training
Key=ManagedBy,Value=acme-sagemaker
Key=Company,Value=acme
```

---

## 依赖关系

```
lib/iam-core.sh
    ↓ 复用模板
01-iam/policies/*.json.tpl

08-operations/
    ↓ 调用
lib/*.sh
```

---

## 模块使用情况

| 模块                       | iam-core | discovery | s3-factory | sagemaker-factory |
| -------------------------- | :------: | :-------: | :--------: | :---------------: |
| 01-iam/01-create-policies  |    ✅    |     -     |     -      |         -         |
| 01-iam/02-create-groups    |    ✅    |     -     |     -      |         -         |
| 01-iam/03-create-users     |    ✅    |     -     |     -      |         -         |
| 01-iam/04-create-roles     |    ✅    |     -     |     -      |         -         |
| 01-iam/05-bind-policies    |    ✅    |     -     |     -      |         -         |
| 01-iam/06-add-users-groups |    ✅    |     -     |     -      |         -         |
| 01-iam/cleanup             |    ✅    |     -     |     -      |         -         |
| 03-s3/01-create-buckets    |    -     |     -     |     ✅     |         -         |
| 03-s3/cleanup              |    -     |     -     |     ✅     |         -         |
| 05-user-profiles           |    -     |     -     |     -      |        ✅         |
| 08-operations              |    ✅    |    ✅     |     ✅     |        ✅         |

### 复用的函数

**01-iam:**

- `create_policy()` - 由 01-create-policies.sh 调用
- `create_iam_group()` / `create_team_group()` / `create_project_group()` - 由 02-create-groups.sh 调用
- `create_iam_user()` / `create_admin_user()` - 由 03-create-users.sh 调用
- `create_domain_default_role()` - 由 04-create-roles.sh 调用
- `create_execution_role()` / `create_training_role()` / `create_processing_role()` / `create_inference_role()` - 由 04-create-roles.sh 调用
- `attach_canvas_policies()` / `attach_studio_app_permissions()` / `attach_mlflow_app_access()` - 由 04-create-roles.sh 调用
- `attach_policy_to_group()` / `bind_team_policies()` / `bind_policies_to_project_group()` - 由 05-bind-policies.sh 调用
- `add_user_to_group()` - 由 06-add-users-to-groups.sh 调用
- `delete_iam_*()` - 由 cleanup.sh 调用

**05-user-profiles:**

- `create_user_profile()` - 由 01-create-user-profiles.sh 调用
- `create_private_space()` - 由 02-create-private-spaces.sh 调用
- `get_studio_sg()` / `get_studio_security_group()` - 获取安全组
- `get_project_short()` - 由全部脚本调用 (setup-all, create, cleanup, verify)
- `delete_private_space()` / `delete_sagemaker_user_profile()` - 由 cleanup.sh 调用

**08-operations:**

- 使用全部 lib 函数（创建/删除 IAM、S3、SageMaker 资源）
