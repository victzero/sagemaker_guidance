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

## 10. 待完善内容

- [ ] Space 创建 CLI/CloudFormation 命令
- [ ] 成员管理自动化脚本
- [ ] 存储监控和告警
- [ ] 协作最佳实践指南

---

## 11. 检查清单

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
