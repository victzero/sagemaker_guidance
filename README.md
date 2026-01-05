# SageMaker AI/ML 平台构建手册

> AWS SageMaker 平台搭建的完整指南

## 📖 在线阅读

**本地预览：**

```bash
# 安装依赖
npm install

# 启动本地服务器
npm run dev

# 浏览器访问
open http://localhost:3000
```

**或者使用 Python 简单服务器：**

```bash
cd docs
python -m http.server 3000

# 浏览器访问
open http://localhost:3000
```

## 📁 文档结构

```
docs/
├── README.md                      # 文档首页
├── 01-architecture-overview.md    # 整体架构设计
├── 02-iam-design.md              # IAM 权限体系（4 角色设计）
├── 03-vpc-network.md             # VPC 网络配置
├── 04-s3-data-management.md      # S3 数据管理
├── 05-sagemaker-domain.md        # SageMaker Domain（内置 Idle Shutdown）
├── 06-user-profile.md            # User Profile + Private Space 设计
├── 08-implementation-guide.md    # 实施步骤指南
├── 09-appendix.md                # 附录与参考
├── 10-sagemaker-processing.md    # Processing Jobs
├── 11-data-wrangler.md           # Data Wrangler
├── 12-sagemaker-training.md      # Training Jobs
└── 13-realtime-inference.md      # Real-Time Inference
```

## 🚀 部署到 GitHub Pages

1. **创建 GitHub 仓库**

2. **推送代码**
```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin git@github.com:YOUR_USERNAME/sagemaker-guidance.git
git push -u origin main
```

3. **启用 GitHub Pages**
   - 进入仓库 Settings → Pages
   - Source 选择 `main` 分支
   - Folder 选择 `/docs`
   - 保存后等待部署

4. **访问**
   - `https://YOUR_USERNAME.github.io/sagemaker-guidance/`

## 🛠️ 技术栈

- [Docsify](https://docsify.js.org/) - 文档网站生成器
- Markdown - 文档格式
- GitHub Pages - 静态托管

## 📝 贡献指南

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/new-section`)
3. 提交更改 (`git commit -m 'Add new section'`)
4. 推送分支 (`git push origin feature/new-section`)
5. 创建 Pull Request

