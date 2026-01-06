# scripts/lib - 共享函数库

供多个模块复用的核心函数库。

## 设计原则

1. **01-07 模块是权威实现** - lib 中的函数从 01-iam 等模块提取
2. **不重复实现** - lib 复用 01-iam/policies 中的模板
3. **01-07 行为不变** - lib 只是将核心函数提取出来供复用

---

## 文件说明

| 文件                   | 说明                                       |
| ---------------------- | ------------------------------------------ |
| `iam-core.sh`          | IAM 核心函数（模板渲染、策略/角色创建）    |
| `discovery.sh`         | 动态资源发现（从 AWS 查询团队/项目）       |
| `s3-factory.sh`        | S3 Bucket 创建函数                         |
| `sagemaker-factory.sh` | User Profile、Space 创建函数               |

---

## 使用方式

```bash
# 在脚本中加载
source "${SCRIPTS_ROOT}/lib/iam-core.sh"
source "${SCRIPTS_ROOT}/lib/discovery.sh"
source "${SCRIPTS_ROOT}/lib/s3-factory.sh"
source "${SCRIPTS_ROOT}/lib/sagemaker-factory.sh"

# 使用函数
render_template "path/to/template.json.tpl" "VAR1=value1"
discover_projects_for_team "rc"
create_project_bucket "rc" "fraud-detection"
create_user_profile "$DOMAIN_ID" "profile-name" "$role_arn" ...
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

| 模块             | iam-core | discovery | s3-factory | sagemaker-factory |
| ---------------- | :------: | :-------: | :--------: | :---------------: |
| 01-iam           |    ✅    |     -     |     -      |         -         |
| 08-operations    |    ✅    |    ✅     |     ✅     |        ✅         |
