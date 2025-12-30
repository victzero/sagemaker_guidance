# 11 - SageMaker Data Wrangler

> 可视化数据准备工具快速入门

---

## 快速开始

> ✅ **前提条件**：已完成 Phase 1 基础设施部署，可登录 SageMaker Studio

### 打开 Data Wrangler

1. 登录 SageMaker Studio
2. 点击左侧 **File** 菜单
3. 选择 **New** → **Data Wrangler Flow**
4. 等待 Data Wrangler 应用启动（首次约 3-5 分钟）

---

## 1. Data Wrangler 概述

### 1.1 什么是 Data Wrangler

SageMaker Data Wrangler 是可视化数据准备工具：

- **无代码/低代码**：拖拽式数据转换
- **300+ 内置转换**：预定义的数据处理操作
- **数据可视化**：内置数据分析和可视化
- **导出能力**：生成 Processing Job / Pipeline 代码

### 1.2 适用场景

| 场景 | 推荐度 | 说明 |
|------|--------|------|
| 快速数据探索 | ⭐⭐⭐⭐⭐ | 最佳场景 |
| 特征工程原型 | ⭐⭐⭐⭐ | 可视化验证 |
| 生成处理代码 | ⭐⭐⭐⭐ | 导出 Python 代码 |
| 大规模处理 | ⭐⭐ | 建议导出为 Processing Job |

### 1.3 与其他工具对比

| 工具 | 适用场景 | 学习曲线 | 灵活性 |
|------|----------|----------|--------|
| **Data Wrangler** | 可视化数据探索 | 低 | 中 |
| **Notebook** | 自定义代码处理 | 中 | 高 |
| **Processing Job** | 生产级批处理 | 中 | 高 |
| **Glue** | 大规模 ETL | 高 | 高 |

---

## 2. 典型工作流

```
1. 导入数据（S3）
    │
    ▼
2. 数据分析（统计、分布、缺失值）
    │
    ▼
3. 数据转换（清洗、编码、特征工程）
    │
    ▼
4. 导出（S3 / Processing Job / Notebook）
```

---

## 3. 导入数据

### 3.1 从 S3 导入

1. 在 Data Wrangler 中点击 **Import data**
2. 选择 **Amazon S3**
3. 浏览到项目 Bucket：`s3://{company}-sm-{team}-{project}/`
4. 选择要处理的数据文件（CSV/Parquet/JSON）
5. 点击 **Import**

### 3.2 支持的数据格式

| 格式 | 推荐度 | 说明 |
|------|--------|------|
| **CSV** | ⭐⭐⭐⭐⭐ | 通用格式 |
| **Parquet** | ⭐⭐⭐⭐⭐ | 大数据推荐 |
| **JSON** | ⭐⭐⭐ | 需要扁平化 |

### 3.3 采样设置

对于大数据集，建议使用采样：

| 数据大小 | 采样建议 |
|----------|----------|
| < 1 GB | 全量加载 |
| 1-10 GB | 采样 100K-500K 行 |
| > 10 GB | 采样 50K-100K 行 |

---

## 4. 数据分析

### 4.1 自动数据分析

导入数据后，Data Wrangler 自动提供：

- **数据类型识别**：自动检测列类型
- **统计摘要**：均值、中位数、标准差
- **分布可视化**：直方图、箱线图
- **缺失值报告**：缺失比例和模式

### 4.2 数据质量报告

点击 **Data Quality and Insights Report** 获取：

- 重复行检测
- 异常值识别
- 特征相关性
- 目标泄漏检测

---

## 5. 常用数据转换

### 5.1 数据清洗

| 转换 | 用途 | 操作路径 |
|------|------|----------|
| **Handle missing** | 处理缺失值 | Transform → Handle missing |
| **Remove duplicates** | 删除重复行 | Transform → Manage rows |
| **Drop columns** | 删除列 | Transform → Manage columns |
| **Filter rows** | 过滤行 | Transform → Filter |

### 5.2 特征工程

| 转换 | 用途 | 操作路径 |
|------|------|----------|
| **One-hot encoding** | 类别编码 | Transform → Encode categorical |
| **Standardize** | 标准化 | Transform → Scale values |
| **Normalize** | 归一化 | Transform → Scale values |
| **Binning** | 分箱 | Transform → Custom transform |

### 5.3 自定义转换（Python/Pandas）

```python
# 在 Custom Transform 中使用
# 输入 DataFrame 名为 df

# 示例：创建新特征
df['amount_log'] = np.log1p(df['amount'])

# 示例：组合特征
df['ratio'] = df['col_a'] / (df['col_b'] + 1)
```

---

## 6. 导出数据

### 6.1 导出到 S3

1. 点击 **Export** 标签
2. 选择 **Export to** → **Amazon S3**
3. 配置输出路径：`s3://{bucket}/processed/`
4. 选择输出格式（CSV/Parquet）
5. 点击 **Export data**

### 6.2 导出为 Processing Job

将 Data Wrangler 流程转为可调度的 Processing Job：

1. 点击 **Export** → **Amazon SageMaker Pipeline (via Processing Job)**
2. 生成的 Notebook 包含完整的 Processing Job 代码
3. 可直接运行或集成到 Pipeline

### 6.3 导出为 Python 代码

1. 点击 **Export** → **Python code**
2. 获取 Pandas 代码，可在 Notebook 中使用

---

## 7. 最佳实践

### 7.1 工作流建议

```
开发阶段:
├── 使用 Data Wrangler 探索数据
├── 可视化验证转换效果
└── 确定最终处理逻辑

生产阶段:
├── 导出为 Processing Job
├── 在 Pipeline 中自动运行
└── 处理全量数据
```

### 7.2 性能优化

| 建议 | 原因 |
|------|------|
| 使用采样 | 加快交互响应 |
| 及时保存 Flow | 避免丢失工作 |
| 定期导出 | 保存处理逻辑 |

### 7.3 成本控制

Data Wrangler 使用 `ml.m5.4xlarge` 实例：

| 操作 | 建议 |
|------|------|
| 不使用时 | 关闭 Data Wrangler 应用 |
| 长时间不用 | 保存 Flow 后删除应用 |

关闭应用：
1. 点击左侧 **Running Terminals and Kernels**
2. 找到 Data Wrangler 应用
3. 点击 **Shut Down**

---

## 8. 示例：欺诈检测数据准备

### 8.1 场景描述

准备交易数据用于欺诈检测模型训练。

### 8.2 数据转换流程

```
原始数据
    │
    ├── 1. 删除缺失值 (Handle missing)
    │
    ├── 2. 删除重复交易 (Remove duplicates)
    │
    ├── 3. 金额取对数 (Custom: log transform)
    │
    ├── 4. 类别编码 (One-hot encoding)
    │
    ├── 5. 标准化数值 (Standardize)
    │
    └── 6. 导出到 S3
```

### 8.3 Custom Transform 示例

```python
# 金额取对数
import numpy as np
df['amount_log'] = np.log1p(df['amount'].clip(lower=0))

# 时间特征提取
df['hour'] = pd.to_datetime(df['timestamp']).dt.hour
df['day_of_week'] = pd.to_datetime(df['timestamp']).dt.dayofweek
df['is_weekend'] = df['day_of_week'].isin([5, 6]).astype(int)
```

---

## 9. 故障排查

### 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 启动慢 | 首次启动需要拉取镜像 | 等待 3-5 分钟 |
| 导入失败 | S3 权限不足 | 检查 Execution Role |
| 内存不足 | 数据量过大 | 使用采样 |
| 保存失败 | EFS 空间不足 | 清理旧文件 |

### 检查 S3 权限

```python
# 在 Notebook 中测试 S3 访问
import boto3
s3 = boto3.client('s3')

bucket = 'acme-sm-rc-fraud-detection'
try:
    response = s3.list_objects_v2(Bucket=bucket, MaxKeys=5)
    print(f"Access OK. Found {len(response.get('Contents', []))} objects.")
except Exception as e:
    print(f"Access denied: {e}")
```

---

## 10. 检查清单

### ✅ 开始前

- [ ] 可以登录 SageMaker Studio
- [ ] S3 数据已上传到项目 Bucket
- [ ] 了解数据结构和业务含义

### ✅ 使用中

- [ ] 使用采样加速探索
- [ ] 定期保存 Flow
- [ ] 记录转换逻辑

### ✅ 完成后

- [ ] 导出处理后的数据
- [ ] 保存 Flow 文件（.flow）
- [ ] 关闭 Data Wrangler 应用节省成本

---

## 下一步

- [12 - SageMaker Training](12-sagemaker-training.md) - 模型训练
- [10 - SageMaker Processing](10-sagemaker-processing.md) - 生产级数据处理
