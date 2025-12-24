# 07 - Shared Space 设计

> 本文档描述 SageMaker Shared Space（共享空间）的设计

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符        | 说明               | 示例值                   |
| ------------- | ------------------ | ------------------------ |
| `{company}`   | 公司/组织名称前缀  | `acme`                   |
| `{team}`      | 团队缩写           | `rc`、`algo`             |
| `{project}`   | 项目名称           | `project-a`、`project-x` |
| `{owner}`     | 空间所有者 Profile | `profile-rc-alice`       |
| `d-xxxxxxxxx` | Domain ID          | `d-abc123def456`         |

---

## 1. Space 概述

### 1.1 什么是 Space

SageMaker Space 是用于协作的共享环境：

- 项目团队成员可以共享 Notebook
- 共享计算资源和存储
- 支持实时协作编辑

### 1.2 Space 类型

| 类型             | 说明       | 用途        |
| ---------------- | ---------- | ----------- |
| **Shared Space** | 多用户共享 | 项目协作 ✅ |
| Private Space    | 单用户独占 | 个人实验    |

**本项目选择**：主要使用 Shared Space

---

## 2. Space 规划

### 2.1 Space 清单

| Space Name           | 团队 | 项目      | 成员                | Execution Role              |
| -------------------- | ---- | --------- | ------------------- | --------------------------- |
| space-rc-project-a   | 风控 | project-a | alice, bob, carol   | RC-ProjectA-ExecutionRole   |
| space-rc-project-b   | 风控 | project-b | david, emma         | RC-ProjectB-ExecutionRole   |
| space-algo-project-x | 算法 | project-x | frank, grace, henry | Algo-ProjectX-ExecutionRole |
| space-algo-project-y | 算法 | project-y | ivy, jack           | Algo-ProjectY-ExecutionRole |

### 2.2 命名规范

```
Space 名称: space-{team}-{project}

示例:
- space-rc-project-a     # 风控项目A
- space-algo-project-x   # 算法项目X
```

---

## 3. Space 配置

### 3.1 核心配置

| 配置项                                 | 值                     | 说明        |
| -------------------------------------- | ---------------------- | ----------- |
| SpaceName                              | space-{team}-{project} | 空间名称    |
| DomainId                               | d-xxxxxxxxx            | 所属 Domain |
| OwnershipSettings.OwnerUserProfileName | (项目负责人)           | 空间所有者  |
| SpaceSharingSettings.SharingType       | Shared                 | 共享类型    |

### 3.2 Space 设置

| 配置项          | 推荐值       | 说明     |
| --------------- | ------------ | -------- |
| AppType         | JupyterLab   | 应用类型 |
| InstanceType    | ml.t3.medium | 默认实例 |
| EBS Volume Size | 50 GB        | 共享存储 |

---

## 4. 成员权限设计

### 4.1 成员角色

| 角色        | 权限     | 说明                    |
| ----------- | -------- | ----------------------- |
| Owner       | 完全控制 | 创建、删除、管理成员    |
| Contributor | 读写     | 使用 Notebook、上传文件 |
| Viewer      | 只读     | 查看 Notebook           |

### 4.2 成员配置

```
space-rc-project-a:
├── Owner: profile-rc-alice (项目负责人)
├── Contributor: profile-rc-bob
└── Contributor: profile-rc-carol

space-algo-project-x:
├── Owner: profile-algo-frank (项目负责人)
├── Contributor: profile-algo-grace
└── Contributor: profile-algo-henry
```

---

## 5. Space 与权限关系

### 5.1 访问控制

用户访问 Space 需要：

1. **IAM 权限**：用户所在 Group 有 Space 访问权限
2. **Space 成员**：用户的 Profile 是 Space 成员
3. **Domain 归属**：用户 Profile 在同一 Domain

### 5.2 数据访问

Space 内的用户共享：

- Notebook 文件
- Space EBS 存储
- 通过 Execution Role 访问的 S3 数据

---

## 6. Space 存储

### 6.1 存储结构

```
Space 存储 (EBS):
/home/sagemaker-user/
├── notebooks/          # 共享 Notebook
├── data/              # 共享数据
└── outputs/           # 输出结果

+ S3 Bucket (项目级):
s3://{company}-sm-{team}-{project}/
```

### 6.2 存储配额

| 存储类型        | 大小   | 说明         |
| --------------- | ------ | ------------ |
| Space EBS       | 50 GB  | 共享工作空间 |
| User Home (EFS) | 按需   | 个人配置文件 |
| S3              | 无限制 | 项目数据     |

---

## 7. 协作功能

### 7.1 实时协作

Shared Space 支持：

- 多人同时编辑 Notebook
- 实时同步
- 查看其他用户光标

### 7.2 协作注意事项

| 场景              | 建议               |
| ----------------- | ------------------ |
| 同时编辑同一 Cell | 可能冲突，建议协调 |
| 长时运行任务      | 使用独立 Notebook  |
| 大数据处理        | 输出到 S3 而非本地 |

---

## 8. Space 生命周期

### 8.1 创建流程

```
1. 确认 Domain 和 User Profiles 已创建
2. 创建 Space
3. 配置 Space Settings
4. 添加成员 (通过 IAM 控制)
5. 验证访问
```

### 8.2 日常管理

| 操作     | 说明                                |
| -------- | ----------------------------------- |
| 添加成员 | 创建 User Profile + 更新 IAM Policy |
| 移除成员 | 更新 IAM Policy（Profile 可保留）   |
| 扩容存储 | 修改 EBS Size                       |
| 更换实例 | 修改 InstanceType                   |

---

## 9. 标签设计

| Tag Key     | Tag Value  | 示例             |
| ----------- | ---------- | ---------------- |
| Team        | {team}     | risk-control     |
| Project     | {project}  | project-a        |
| Environment | production | production       |
| Owner       | {owner}    | profile-rc-alice |

---

## 10. CLI 创建命令

### 10.1 创建 Shared Space

```bash
# 创建 Shared Space
aws sagemaker create-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a \
  --space-sharing-settings '{
    "SharingType": "Shared"
  }' \
  --ownership-settings '{
    "OwnerUserProfileName": "profile-rc-alice"
  }' \
  --space-settings '{
    "AppType": "JupyterLab",
    "SpaceStorageSettings": {
      "EbsStorageSettings": {
        "EbsVolumeSizeInGb": 50
      }
    }
  }' \
  --tags \
    Key=Team,Value=risk-control \
    Key=Project,Value=project-a \
    Key=Environment,Value=production \
    Key=Owner,Value=profile-rc-alice
```

### 10.2 查询 Space

```bash
# 列出 Domain 下所有 Spaces
aws sagemaker list-spaces --domain-id d-xxxxxxxxx

# 查看单个 Space 详情
aws sagemaker describe-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a
```

### 10.3 更新 Space 设置

```bash
# 更新 Space 存储大小
aws sagemaker update-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a \
  --space-settings '{
    "AppType": "JupyterLab",
    "SpaceStorageSettings": {
      "EbsStorageSettings": {
        "EbsVolumeSizeInGb": 100
      }
    }
  }'
```

### 10.4 删除 Space

```bash
# 先删除 Space 中运行的 Apps
aws sagemaker list-apps \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a

# 删除 App（如有）
aws sagemaker delete-app \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a \
  --app-type JupyterLab \
  --app-name default

# 等待 App 删除后，删除 Space
aws sagemaker delete-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a
```

---

## 11. 批量创建与成员管理脚本

### 11.1 Space 配置文件 `spaces.csv`

```csv
space_name,team,project,owner_profile,execution_role,members
space-rc-project-a,risk-control,project-a,profile-rc-alice,RC-ProjectA-ExecutionRole,profile-rc-bob;profile-rc-carol
space-rc-project-b,risk-control,project-b,profile-rc-david,RC-ProjectB-ExecutionRole,profile-rc-emma
space-algo-project-x,algorithm,project-x,profile-algo-frank,Algo-ProjectX-ExecutionRole,profile-algo-grace;profile-algo-henry
space-algo-project-y,algorithm,project-y,profile-algo-ivy,Algo-ProjectY-ExecutionRole,profile-algo-jack
```

### 11.2 批量创建 Space 脚本 `create-spaces.sh`

```bash
#!/bin/bash
# create-spaces.sh - 批量创建 Shared Spaces
# 用法: ./create-spaces.sh <domain-id> <spaces.csv>

set -e

DOMAIN_ID="${1:?Usage: $0 <domain-id> <spaces.csv>}"
SPACES_FILE="${2:?Usage: $0 <domain-id> <spaces.csv>}"
EBS_SIZE=50  # 默认 EBS 大小（GB）

# 跳过 CSV 头行
tail -n +2 "$SPACES_FILE" | while IFS=',' read -r space_name team project owner_profile execution_role members; do
    echo "Creating Space: $space_name"

    # 检查是否已存在
    if aws sagemaker describe-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" >/dev/null 2>&1; then
        echo "  → Already exists, skipping."
        continue
    fi

    # 创建 Space
    aws sagemaker create-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" \
        --space-sharing-settings '{"SharingType": "Shared"}' \
        --ownership-settings "{\"OwnerUserProfileName\": \"${owner_profile}\"}" \
        --space-settings "{
            \"AppType\": \"JupyterLab\",
            \"SpaceStorageSettings\": {
                \"EbsStorageSettings\": {
                    \"EbsVolumeSizeInGb\": ${EBS_SIZE}
                }
            }
        }" \
        --tags \
            Key=Team,Value="$team" \
            Key=Project,Value="$project" \
            Key=Environment,Value=production \
            Key=Owner,Value="$owner_profile"

    echo "  → Created successfully."
    echo "  → Owner: $owner_profile"
    echo "  → Members: $members"

    sleep 1
done

echo ""
echo "Batch creation completed."
aws sagemaker list-spaces --domain-id "$DOMAIN_ID" --query 'Spaces[].SpaceName'
```

### 11.3 成员权限管理

> 📌 SageMaker Space 的成员管理通过 **IAM Policy** 控制，而非 Space API。需要在 IAM Group/User Policy 中配置。

**成员访问控制 IAM Policy 模板**：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccessToProjectSpace",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp",
        "sagemaker:DescribeApp",
        "sagemaker:DescribeSpace",
        "sagemaker:ListApps"
      ],
      "Resource": [
        "arn:aws:sagemaker:{region}:{account-id}:space/d-xxxxxxxxx/space-{team}-{project}",
        "arn:aws:sagemaker:{region}:{account-id}:app/d-xxxxxxxxx/space-{team}-{project}/*"
      ]
    }
  ]
}
```

**添加成员流程**：

```bash
# 1. 确保成员有 User Profile
aws sagemaker describe-user-profile \
  --domain-id d-xxxxxxxxx \
  --user-profile-name profile-rc-newmember

# 2. 将成员添加到对应的 IAM Group（Group 已有 Space 访问策略）
aws iam add-user-to-group \
  --group-name sagemaker-rc-project-a \
  --user-name sm-rc-newmember

# 3. 验证成员可以访问 Space
```

**移除成员流程**：

```bash
# 从 IAM Group 移除即可（无需删除 User Profile）
aws iam remove-user-from-group \
  --group-name sagemaker-rc-project-a \
  --user-name sm-rc-leavingmember
```

---

## 12. 存储监控和告警

### 12.1 EBS 存储监控

```bash
# 查看 Space 关联的 EBS Volume（需要通过 App 查找）
aws sagemaker list-apps \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a

# 获取 Space 详细信息
aws sagemaker describe-space \
  --domain-id d-xxxxxxxxx \
  --space-name space-rc-project-a \
  --query 'SpaceSettings.SpaceStorageSettings'
```

### 12.2 CloudWatch 告警配置

**创建 EBS 使用率告警**（通过 CloudWatch Agent 或自定义指标）：

```bash
# 创建告警：Space EBS 使用率超过 80%
aws cloudwatch put-metric-alarm \
  --alarm-name "SpaceEBS-HighUsage-space-rc-project-a" \
  --alarm-description "Space EBS storage usage exceeds 80%" \
  --metric-name "DiskSpaceUtilization" \
  --namespace "SageMaker/Spaces" \
  --dimensions Name=SpaceName,Value=space-rc-project-a \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:{region}:{account-id}:ml-platform-alerts
```

### 12.3 存储使用报告脚本

```bash
#!/bin/bash
# space-storage-report.sh - 生成 Space 存储使用报告
# 用法: ./space-storage-report.sh <domain-id>

DOMAIN_ID="${1:?Usage: $0 <domain-id>}"

echo "=== SageMaker Space Storage Report ==="
echo "Domain: $DOMAIN_ID"
echo "Time: $(date)"
echo ""

printf "%-25s %-15s %-10s\n" "Space Name" "EBS Size (GB)" "Status"
printf "%-25s %-15s %-10s\n" "----------" "------------" "------"

aws sagemaker list-spaces --domain-id "$DOMAIN_ID" --query 'Spaces[].SpaceName' --output text | tr '\t' '\n' | while read -r space_name; do
    SPACE_INFO=$(aws sagemaker describe-space \
        --domain-id "$DOMAIN_ID" \
        --space-name "$space_name" 2>/dev/null)

    EBS_SIZE=$(echo "$SPACE_INFO" | jq -r '.SpaceSettings.SpaceStorageSettings.EbsStorageSettings.EbsVolumeSizeInGb // "N/A"')
    STATUS=$(echo "$SPACE_INFO" | jq -r '.Status // "Unknown"')

    printf "%-25s %-15s %-10s\n" "$space_name" "$EBS_SIZE" "$STATUS"
done

echo ""
echo "=== End of Report ==="
```

---

## 13. 协作最佳实践指南

### 13.1 Notebook 管理

| 实践             | 说明                                      |
| ---------------- | ----------------------------------------- |
| **命名规范**     | `{日期}_{作者}_{主题}.ipynb`              |
| **目录结构**     | 按功能分目录：`/exploration`、`/modeling` |
| **版本控制**     | 定期推送到 CodeCommit，不依赖 Space 存储  |
| **清理临时文件** | 定期清理 `/tmp` 和输出文件                |

### 13.2 协作规范

| 场景              | 推荐做法                                           |
| ----------------- | -------------------------------------------------- |
| **同一 Notebook** | 避免同时编辑同一 Cell；使用 Cell 级别分工          |
| **长时间任务**    | 使用独立 Notebook 或 SageMaker Jobs                |
| **大数据处理**    | 结果输出到 S3，不存 Space EBS                      |
| **环境依赖**      | 使用 `requirements.txt` 固化依赖版本               |
| **敏感数据**      | 禁止在 Notebook 中硬编码凭证；使用 Secrets Manager |

### 13.3 资源使用

| 实践             | 说明                                      |
| ---------------- | ----------------------------------------- |
| **及时关闭 App** | 不使用时关闭 JupyterLab App，节省成本     |
| **选择合适实例** | 日常开发用 `ml.t3.medium`，大任务临时升级 |
| **定期清理数据** | EBS 空间有限，大数据存 S3                 |
| **监控存储使用** | 关注 EBS 使用率告警                       |

### 13.4 冲突处理

```
场景: 两人同时编辑了同一 Notebook

处理流程:
1. 沟通确认各自的修改内容
2. 一人暂停编辑
3. 另一人完成并保存
4. 第一人刷新后继续
5. 如有代码丢失，从 CodeCommit 恢复

预防措施:
- 开始编辑前在团队群通知
- 使用不同 Notebook 并行开发
- 频繁 commit 到 CodeCommit
```

### 13.5 Space 使用 vs 个人 Profile

| 工作类型         | 推荐位置          | 说明                        |
| ---------------- | ----------------- | --------------------------- |
| **团队协作开发** | Shared Space      | 共享 Notebook、实时协作     |
| **个人探索实验** | 个人 User Profile | 避免影响他人                |
| **正式模型训练** | SageMaker Jobs    | 独立资源、可追溯            |
| **代码存档**     | CodeCommit        | 版本控制、不依赖 Space 存储 |
| **数据存储**     | S3 Bucket         | 持久化、权限可控            |

---

## 14. 检查清单

### 创建前

- [ ] Domain 已创建
- [ ] 项目成员的 User Profiles 已创建
- [ ] 项目 Execution Role 已创建
- [ ] 确认项目成员名单

### 创建时

- [ ] 使用正确的命名规范
- [ ] 配置正确的 Execution Role
- [ ] 设置合适的存储大小
- [ ] 添加标签

### 创建后

- [ ] 验证所有成员可以访问
- [ ] 验证成员可以创建 Notebook
- [ ] 验证 S3 数据访问正常
- [ ] 测试协作功能
