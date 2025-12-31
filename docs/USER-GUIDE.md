# SageMaker Studio 用户指南

> 本指南面向 ML 平台的开发者用户

---

## 目录

1. [快速开始](#1-快速开始)
2. [登录 SageMaker Studio](#2-登录-sagemaker-studio)
3. [使用 JupyterLab](#3-使用-jupyterlab)
4. [使用 Shared Space](#4-使用-shared-space)
5. [数据访问](#5-数据访问)
6. [成本控制](#6-成本控制)
7. [常见问题](#7-常见问题)

---

## 1. 快速开始

### 1.1 您的账号信息

平台管理员会提供以下信息：

| 信息项         | 示例值                                               | 您的值 |
| -------------- | ---------------------------------------------------- | ------ |
| IAM 用户名     | `sm-rc-alice`                                        |        |
| 初始密码       | `SmTemp@2024`                                        |        |
| AWS 控制台 URL | `https://123456789012.signin.aws.amazon.com/console` |        |
| 所属团队       | 风控团队 (rc)                                        |        |
| 所属项目       | fraud-detection                                      |        |

### 1.2 首次登录流程（重要！）

```
1. 访问 AWS Console 登录页面
   ↓
2. 输入 IAM 用户名和初始密码
   ↓
3. 首次登录强制修改密码
   ↓
4. ⚠️ 设置 MFA（必须！否则无法访问任何服务）
   ↓
5. ⚠️ 退出登录，重新登录（输入 MFA 验证码）
   ↓
6. 现在可以访问 SageMaker Studio
```

> ⚠️ **关键步骤**：设置 MFA 后**必须退出并重新登录**，否则当前会话没有 MFA token，仍然无法访问服务！

---

## 2. 登录 SageMaker Studio

### 2.1 步骤详解

**Step 1: 登录 AWS Console**

1. 打开浏览器，访问 AWS Console 登录页面
2. 选择 "IAM user" 登录方式
3. 输入账号 ID（12 位数字）或账号别名
4. 输入您的 IAM 用户名和密码
5. **首次登录**：修改密码 → 设置 MFA → **退出重新登录**
6. **后续登录**：输入密码 + MFA 验证码

> 💡 **MFA 设置方法**：登录后，点击右上角用户名 → Security credentials → Assign MFA device

**Step 2: 导航到 SageMaker Studio**

1. 在 AWS Console 顶部搜索栏输入 `SageMaker`
2. 点击 **Amazon SageMaker**
3. 在左侧导航栏选择 **Studio**
4. 点击 **Open Studio**

**Step 3: 选择 User Profile**

1. 在 Studio 启动页面，您会看到您的 User Profile
2. Profile 名称格式：`profile-{team}-{name}`（如 `profile-rc-alice`）
3. 点击您的 Profile 右侧的 **Open** 按钮

> ⚠️ **注意**：您只能看到和访问属于您的 User Profile

**Step 4: 等待 Studio 加载**

- 首次启动可能需要 2-5 分钟
- 后续启动通常在 30 秒内完成

### 2.2 快速登录链接（管理员提供）

管理员可能会为您生成预签名 URL，有效期 5 分钟：

```
https://d-xxxxxxxxx.studio.{region}.sagemaker.aws/auth/presigned?...
```

直接点击此链接即可进入 Studio，无需手动导航。

---

## 3. 使用 JupyterLab

### 3.1 启动 JupyterLab

1. 在 Studio 首页，点击 **JupyterLab**
2. 选择计算配置：
   - **Instance type**: 默认 `ml.t3.medium`（可按需调整）
   - **Image**: 使用默认即可
3. 点击 **Run** 启动

### 3.2 实例规格说明

| 实例类型      | vCPU | 内存  | 适用场景           | 预估费用/小时 |
| ------------- | ---- | ----- | ------------------ | ------------- |
| ml.t3.medium  | 2    | 4 GB  | 日常开发、轻量计算 | ~$0.05        |
| ml.t3.large   | 2    | 8 GB  | 中等数据处理       | ~$0.10        |
| ml.t3.xlarge  | 4    | 16 GB | 较大数据集         | ~$0.20        |
| ml.c5.xlarge  | 4    | 8 GB  | CPU 密集计算       | ~$0.17        |
| ml.c5.2xlarge | 8    | 16 GB | 大规模特征工程     | ~$0.34        |

> 💡 **建议**：从小规格开始，按需升级。GPU 实例费用较高，请谨慎使用。

### 3.3 自动关机

- 系统配置了 **60 分钟空闲自动关机**
- 空闲定义：无活跃的 Jupyter Kernel 运行
- 目的：节省成本，避免忘记关闭实例

### 3.4 手动关闭实例

完成工作后，建议手动关闭实例：

1. 在 JupyterLab 中，点击左侧边栏的 **Running Terminals and Kernels** 图标
2. 关闭所有运行中的 Kernels
3. 返回 Studio 首页
4. 在 Running instances 中点击 **Shut down**

---

## 4. 使用 Shared Space

### 4.1 什么是 Shared Space

- Shared Space 是项目团队的**共享协作空间**
- 同一项目的成员可以访问相同的 Space
- 适合团队协作、代码共享、数据共享

### 4.2 访问 Shared Space

1. 在 Studio 首页，点击 **Shared Spaces**
2. 找到您所属项目的 Space（如 `space-rc-fraud-detection`）
3. 点击 Space 进入

> ⚠️ **注意**：您只能访问所属项目的 Space

### 4.3 在 Space 中创建 JupyterLab

1. 进入 Space 后，点击 **Create JupyterLab space**
2. 选择实例类型
3. 等待 JupyterLab 启动

### 4.4 Space vs Personal Profile

| 特性     | Personal Profile | Shared Space        |
| -------- | ---------------- | ------------------- |
| 数据隔离 | 个人独享         | 团队共享            |
| 文件存储 | 个人 Home 目录   | Space 共享存储      |
| 适用场景 | 个人实验、草稿   | 团队协作、正式项目  |
| EBS 大小 | 继承默认         | 50 GB（可申请扩容） |

---

## 5. 数据访问

### 5.1 S3 数据访问

每个项目有专属的 S3 Bucket：

```
项目 Bucket: s3://{company}-sm-{team}-{project}/
├── data/           # 原始数据
├── processed/      # 处理后数据
├── models/         # 模型文件
├── outputs/        # 输出结果
└── temp/           # 临时文件（7天自动删除）
```

> ⚠️ **注意**：出于安全考虑，您**无法在 S3 控制台看到所有 Bucket 列表**。请使用以下方式访问您的项目 Bucket。

### 5.2 S3 直接 URL 访问（推荐）

由于无法看到 Bucket 列表，请使用**直接 URL** 访问您的项目 Bucket：

**URL 格式：**

```
https://s3.console.aws.amazon.com/s3/buckets/{bucket-name}?region={region}
```

**示例（根据您的项目替换）：**

| 您的项目                   | 直接访问 URL                                                                                            |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| rc/fraud-detection         | `https://s3.console.aws.amazon.com/s3/buckets/acme-sm-rc-fraud-detection?region=ap-northeast-1`         |
| algo/recommendation-engine | `https://s3.console.aws.amazon.com/s3/buckets/acme-sm-algo-recommendation-engine?region=ap-northeast-1` |
| 共享资源                   | `https://s3.console.aws.amazon.com/s3/buckets/acme-sm-shared-assets?region=ap-northeast-1`              |

**Bucket 命名规则：**

```
{company}-sm-{team}-{project}

示例：
- acme-sm-rc-fraud-detection      （风控/欺诈检测）
- acme-sm-rc-anti-money-laundering（风控/反洗钱）
- acme-sm-algo-recommendation-engine（算法/推荐引擎）
- acme-sm-shared-assets            （共享资源，只读）
```

> 💡 **建议**：将您的项目 Bucket URL 加入浏览器书签，方便快速访问

### 5.3 在 Notebook 中访问 S3

```python
import boto3
import pandas as pd

# 读取数据
df = pd.read_csv('s3://acme-sm-rc-fraud-detection/data/train.csv')

# 写入数据
df.to_csv('s3://acme-sm-rc-fraud-detection/processed/train_clean.csv', index=False)

# 列出文件
s3 = boto3.client('s3')
response = s3.list_objects_v2(
    Bucket='acme-sm-rc-fraud-detection',
    Prefix='data/'
)
for obj in response.get('Contents', []):
    print(obj['Key'])
```

### 5.4 共享资源访问

所有项目可**只读**访问共享资源 Bucket：

```python
# 读取共享数据集（只读）
shared_df = pd.read_csv('s3://acme-sm-shared-assets/datasets/common_features.csv')

# 读取共享模型
import joblib
model = joblib.load('s3://acme-sm-shared-assets/models/pretrained_encoder.pkl')
```

### 5.5 数据访问权限

| 操作 | 项目 Bucket | 共享 Bucket | 其他项目 Bucket |
| ---- | ----------- | ----------- | --------------- |
| 读取 | ✅          | ✅          | ❌              |
| 写入 | ✅          | ❌          | ❌              |
| 删除 | ✅          | ❌          | ❌              |

---

## 6. 成本控制

### 6.1 成本意识

| 资源     | 计费方式   | 节省建议                |
| -------- | ---------- | ----------------------- |
| 计算实例 | 按运行时间 | 用完即关，避免空跑      |
| EBS 存储 | 按容量/月  | 定期清理临时文件        |
| S3 存储  | 按容量/月  | 利用 temp/ 目录自动清理 |

### 6.2 最佳实践

1. **选择合适的实例**：从小规格开始，按需升级
2. **及时关闭实例**：完成工作后手动关闭
3. **利用自动关机**：依赖 60 分钟空闲关机作为兜底
4. **清理临时文件**：定期清理 temp/ 目录
5. **使用 temp/ 目录**：临时文件放入 temp/，7 天后自动删除

### 6.3 查看使用情况

在 Studio 首页可以看到：

- 当前运行的实例
- 存储使用情况
- 历史使用统计

---

## 7. 常见问题

### Q1: 无法登录 AWS Console

**可能原因**：

- 用户名或密码错误
- 账号被锁定
- MFA 配置问题

**解决方案**：

1. 确认用户名格式正确（如 `sm-rc-alice`）
2. 联系管理员重置密码
3. 检查 MFA 设备时间是否同步

### Q1.5: 登录后无法访问任何服务（提示 not authorized）

**可能原因**：

- ⚠️ **MFA 未设置或设置后未重新登录**

**解决方案**：

1. 检查是否已设置 MFA：右上角用户名 → Security credentials
2. 如未设置：点击 "Assign MFA device" 设置
3. **关键**：设置 MFA 后**必须退出并重新登录**
4. 重新登录时输入 MFA 验证码
5. 现在应该可以访问服务了

> 💡 设置 MFA 只是在账户上绑定了设备，当前登录会话并没有 MFA token。必须重新登录才能获得带 MFA 的会话。

### Q2: Studio 启动失败或报 "Error acquiring credentials"

**可能原因**：

- ⚠️ MFA 未设置或设置后未重新登录
- 网络问题
- 配额不足
- Execution Role 配置问题

**解决方案**：

1. **首先检查 MFA**：确保已设置 MFA 并重新登录
2. 等待几分钟后重试
3. 尝试选择不同的实例类型
4. 联系管理员检查 Execution Role 和配额

> 💡 "Error acquiring credentials" 通常是因为缺少 MFA 或 IAM 权限不足

### Q3: 看不到 S3 Bucket 列表

**这是正常的！** 出于安全考虑，系统禁止了 `ListAllMyBuckets` 权限。

**解决方案**：

1. 使用**直接 URL** 访问您的项目 Bucket（见 [5.2 S3 直接 URL 访问](#52-s3-直接-url-访问推荐)）
2. 在 SageMaker Studio 内使用文件浏览器
3. 在 Notebook 中使用 boto3 访问

### Q3.5: 无法访问 S3 数据

**可能原因**：

- Bucket 名称错误
- 无访问权限（不是您项目的 Bucket）
- 文件路径错误

**解决方案**：

1. 确认 Bucket 名称正确：`{company}-sm-{team}-{project}`
2. 确认您属于该项目
3. 确认文件路径存在
4. 联系管理员检查权限

### Q4: 无法看到 Shared Space

**可能原因**：

- 您不属于该项目
- Space 尚未创建

**解决方案**：

1. 确认您的项目分配
2. 联系管理员添加权限

### Q5: 实例运行缓慢

**可能原因**：

- 实例规格不足
- 内存不足
- 数据量过大

**解决方案**：

1. 升级到更大实例
2. 优化代码，减少内存使用
3. 分批处理数据

---

## 附录：快速参考

### 命名规范

| 资源类型     | 命名格式                        | 示例                         |
| ------------ | ------------------------------- | ---------------------------- |
| IAM User     | `sm-{team}-{name}`              | `sm-rc-alice`                |
| User Profile | `profile-{team}-{name}`         | `profile-rc-alice`           |
| Shared Space | `space-{team}-{project}`        | `space-rc-fraud-detection`   |
| S3 Bucket    | `{company}-sm-{team}-{project}` | `acme-sm-rc-fraud-detection` |

### 联系方式

| 问题类型 | 联系方式           |
| -------- | ------------------ |
| 账号问题 | 平台管理员         |
| 权限申请 | 项目负责人         |
| 技术支持 | Slack #ml-platform |

---

_最后更新：2024-12_
