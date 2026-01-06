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
| `discovery.sh`         | 动态资源发现（从 AWS 查询团队/项目）             |
| `s3-factory.sh`        | S3 Bucket 创建/删除函数                          |
| `sagemaker-factory.sh` | User Profile、Space 创建/删除函数                |

---

## 核心函数一览

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
| `bind_team_policies <team>` | 绑定团队策略到 Group |
| `bind_policies_to_project_group <team> <project>` | 绑定项目策略到 Group |

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

| 函数                                                    | 说明                 |
| ------------------------------------------------------- | -------------------- |
| `create_project_s3 <team> <project> [--with-lifecycle]` | 创建项目 S3 Bucket   |
| `delete_project_bucket <team> <project>`                | 删除项目 S3 Bucket   |
| `delete_bucket <bucket_name>`                           | 删除 Bucket (含清空) |

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
| 01-iam/06-add-users-groups |    ✅    |     -     |     -      |         -         |
| 01-iam/cleanup             |    ✅    |     -     |     -      |         -         |
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
