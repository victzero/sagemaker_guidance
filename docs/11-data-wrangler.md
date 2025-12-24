# 11 - SageMaker Data Wrangler

> 本文档描述 SageMaker Data Wrangler 的设计与配置

---

## 占位符说明

> 📌 本文档使用以下占位符，实施时请替换为实际值。

| 占位符         | 说明              | 示例值                   |
| -------------- | ----------------- | ------------------------ |
| `{company}`    | 公司/组织名称前缀 | `acme`                   |
| `{account-id}` | AWS 账号 ID       | `123456789012`           |
| `{region}`     | AWS 区域          | `ap-southeast-1`         |
| `{team}`       | 团队缩写          | `rc`、`algo`             |
| `{project}`    | 项目名称          | `project-a`、`project-x` |

---

## 1. Data Wrangler 概述

### 1.1 什么是 Data Wrangler

SageMaker Data Wrangler 是可视化数据准备工具：

- **无代码/低代码**：拖拽式数据转换
- **300+ 内置转换**：预定义的数据处理操作
- **数据可视化**：内置数据分析和可视化
- **导出能力**：生成 Processing Job / Pipeline 代码

### 1.2 与其他工具对比

| 工具             | 适用场景           | 学习曲线 | 灵活性 |
| ---------------- | ------------------ | -------- | ------ |
| **Data Wrangler** | 可视化数据探索    | 低       | 中     |
| **Notebook**     | 自定义代码处理     | 中       | 高     |
| **Processing**   | 生产级批处理       | 中       | 高     |
| **Glue**         | 大规模 ETL         | 高       | 高     |

### 1.3 典型工作流

```
1. 导入数据（S3/Athena/Redshift）
    │
    ▼
2. 数据分析（统计、分布、缺失值）
    │
    ▼
3. 数据转换（清洗、编码、特征工程）
    │
    ▼
4. 导出（Processing Job / Pipeline / Notebook）
```

---

## 2. 权限设计

### 2.1 Data Wrangler 权限模型

Data Wrangler 在 Studio 中运行，使用 User Profile 的 Execution Role：

```
用户 (Studio)
    │
    │ 打开 Data Wrangler
    ▼
Data Wrangler App (ml.m5.4xlarge)
    │
    │ 使用 Execution Role
    ▼
数据源
├── S3 Bucket
├── Athena（可选）
└── Redshift（可选）
```

### 2.2 Execution Role 追加权限

在现有 Execution Role 基础上追加：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DataWranglerS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::{company}-sm-{team}-{project}",
        "arn:aws:s3:::{company}-sm-{team}-{project}/*"
      ]
    },
    {
      "Sid": "DataWranglerAthenaAccess",
      "Effect": "Allow",
      "Action": [
        "athena:StartQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:StopQueryExecution",
        "athena:GetWorkGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "athena:workGroup": "{team}-workgroup"
        }
      }
    },
    {
      "Sid": "GlueDataCatalogAccess",
      "Effect": "Allow",
      "Action": [
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetPartitions"
      ],
      "Resource": [
        "arn:aws:glue:{region}:{account-id}:catalog",
        "arn:aws:glue:{region}:{account-id}:database/{team}_*",
        "arn:aws:glue:{region}:{account-id}:table/{team}_*/*"
      ]
    }
  ]
}
```

---

## 3. 数据源配置

### 3.1 支持的数据源

| 数据源    | 配置要求               | 适用场景         |
| --------- | ---------------------- | ---------------- |
| **S3**    | Execution Role 有权限  | 文件数据         |
| **Athena** | Workgroup + Catalog   | 结构化查询       |
| **Redshift** | Cluster + Secrets   | 数仓数据         |
| **Snowflake** | 连接器 + 凭证      | 外部数仓         |

### 3.2 S3 数据导入

```
数据路径规范:
s3://{company}-sm-{team}-{project}/raw/

支持格式:
- CSV
- Parquet
- JSON
- ORC
```

### 3.3 Athena 数据导入

```sql
-- Athena 查询示例
SELECT *
FROM {team}_database.{project}_table
WHERE partition_date = '2024-01-01'
LIMIT 10000
```

---

## 4. 数据转换

### 4.1 常用转换类型

| 类别         | 转换操作               | 说明               |
| ------------ | ---------------------- | ------------------ |
| **清洗**     | 处理缺失值、去重       | 数据质量           |
| **类型转换** | 字符串→数值、日期解析  | 格式标准化         |
| **编码**     | One-Hot、Label 编码    | 类别特征处理       |
| **数值处理** | 标准化、归一化、分箱   | 特征工程           |
| **文本处理** | 分词、向量化           | NLP 特征           |
| **聚合**     | 分组统计               | 特征衍生           |

### 4.2 自定义转换（Python）

```python
# 自定义 Pandas 转换
def custom_transform(df):
    df['new_feature'] = df['col_a'] * df['col_b']
    return df
```

---

## 5. 导出与集成

### 5.1 导出选项

| 导出目标           | 说明                           | 适用场景       |
| ------------------ | ------------------------------ | -------------- |
| **S3**             | 直接导出处理后数据             | 快速验证       |
| **Processing Job** | 生成 Processing Job 代码       | 生产化         |
| **Pipeline**       | 生成 SageMaker Pipeline 步骤   | ML Pipeline    |
| **Feature Store**  | 写入 Feature Group             | 特征复用       |
| **Notebook**       | 导出 Pandas 代码               | 代码审查       |

### 5.2 导出为 Processing Job

```python
# Data Wrangler 自动生成的代码示例
from sagemaker.processing import ProcessingInput, ProcessingOutput
from sagemaker.sklearn.processing import SKLearnProcessor

# 使用 Data Wrangler 生成的 .flow 文件
flow_file_path = 's3://{company}-sm-{team}-{project}/data-wrangler/{flow-name}.flow'
```

---

## 6. 成本控制

### 6.1 Data Wrangler 实例

| 配置项             | 默认值           | 说明                 |
| ------------------ | ---------------- | -------------------- |
| 实例类型           | ml.m5.4xlarge    | 固定，无法更改       |
| 按需计费           | ~$0.92/小时      | 运行时计费           |
| 自动关闭           | 需手动配置       | **建议启用**         |

### 6.2 成本优化建议

| 策略                   | 说明                             |
| ---------------------- | -------------------------------- |
| **及时关闭**           | 不使用时关闭 Data Wrangler App   |
| **采样数据**           | 探索阶段使用数据采样             |
| **导出后处理**         | 验证后导出为 Processing Job      |
| **Lifecycle Config**   | 配置空闲自动关闭                 |

---

## 7. 工作流文件管理

### 7.1 .flow 文件

Data Wrangler 的工作流保存为 `.flow` 文件：

```
存储路径:
s3://{company}-sm-{team}-{project}/data-wrangler/
├── {project}-feature-eng.flow
├── {project}-data-cleaning.flow
└── exports/
    └── {job-name}/
```

### 7.2 版本管理

| 实践               | 说明                           |
| ------------------ | ------------------------------ |
| **命名规范**       | `{project}-{purpose}-v{n}.flow` |
| **定期备份**       | 导出到 S3                       |
| **代码导出**       | 保存生成的 Python 代码到 Git   |

---

## 8. 与现有架构集成

### 8.1 权限复用

- **Execution Role**：复用 Studio 项目级 Role
- **S3 Bucket**：复用项目 Bucket
- **VPC**：继承 Domain VPC 配置

### 8.2 数据隔离

Data Wrangler 遵循现有隔离策略：
- 只能访问所属项目的 S3 路径
- 只能查询所属团队的 Athena 数据库

---

## 9. 待完善内容

- [ ] Athena 集成详细配置
- [ ] Redshift 集成配置
- [ ] Feature Store 导出配置
- [ ] 完整权限 Policy JSON

---

## 10. 检查清单

### 使用前

- [ ] Execution Role 有 S3 读写权限
- [ ] （如需）Athena Workgroup 已配置
- [ ] 数据已上传到指定 S3 路径

### 使用中

- [ ] 使用数据采样进行探索
- [ ] 定期保存 .flow 文件
- [ ] 记录转换步骤

### 使用后

- [ ] 关闭 Data Wrangler App
- [ ] 导出处理代码
- [ ] 验证输出数据

