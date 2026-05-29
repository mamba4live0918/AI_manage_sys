# 公司AI场景建设管理系统

全链路AI赋能管理平台，一套 Flutter 代码编译 **Windows .exe / Android .apk / Web** 三端，FastAPI 后端提供 REST API。覆盖市场部、招投标合同中心、项目管理中台、HR、财务五大业务域 + 讲师IP专属子系统 + 全系统权限化文件预览。

**当前进度：阶段五进行中**

## 技术栈

```
Flutter 3.44 (Riverpod)  ←→  FastAPI 0.115  ←→  PostgreSQL 16
     ↕ 三端编译              ↕ async            Redis 7
  .exe .apk .web          REST API            MinIO
                                               DeepSeek / Qwen2.5 14B (LLM)
                                               LibreOffice (文档预览)
```

## 快速开始

### 1. 启动基础设施

```bash
docker compose up -d
# PostgreSQL (5432) + Redis (6379) + MinIO (9000/9001) + OnlyOffice (8088)
```

### 2. 启动后端

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
# Swagger: http://localhost:8000/docs
```

### 3. 启动Flutter（选择目标平台）

```bash
cd frontend
flutter pub get
# Windows
flutter run -d windows
# Web
flutter run -d chrome
# Android
flutter run -d android
# iOS (macOS only)
flutter run -d ios
```

### 4. 编译发布版本

```bash
flutter build windows    # → build/windows/x64/runner/Release/*.exe
flutter build apk        # → build/app/outputs/flutter-apk/app-release.apk
flutter build ios        # → 需macOS + Xcode
flutter build web        # → build/web/
```

## 项目结构

```
AI_manage_sys/
├── CLAUDE.md                    # AI助手上下文
├── README.md                    # 本文件
├── TODO.md                      # 全项目任务清单
├── docker-compose.yml           # 开发基础设施
├── docs/
│   └── SRS.md                   # 原始需求文档
├── backend/                     # FastAPI后端
│   ├── requirements.txt
│   ├── init.sql                 # 数据库初始化
│   └── app/
│       ├── main.py              # 入口
│       ├── config.py            # 配置
│       ├── security.py          # JWT + 密码
│       ├── models/              # ORM模型
│       ├── api/                 # 路由（70+ 端点）
│       │   ├── auth.py          # 注册/登录/部门模块
│       │   ├── files.py         # 文件管理
│       │   ├── preview.py       # 预览/下载
│       │   ├── permissions.py   # 权限配置
│       │   ├── audit.py         # 审计日志
│       │   ├── copywriting.py   # 讲师IP AI文案
│       │   ├── marketing.py     # 市场部（阶段三）
│       │   ├── bidding.py       # 招投标（阶段三）
│       │   ├── pm.py            # 项目管理（阶段四）
│       │   ├── hr.py            # HR（阶段四）
│       │   └── finance.py       # 财务（阶段四）
│       └── services/            # 业务逻辑
│           ├── storage.py       # MinIO
│           ├── permission_checker.py  # 5级ACL引擎
│           ├── audit.py         # 审计写入
│           ├── file_extractor.py  # PDF/DOCX/XLSX文本提取
│           └── llm/             # LLM抽象层（OpenAI兼容协议）
└── frontend/                    # Flutter全端
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── app.dart
        ├── config/
        ├── models/
        ├── providers/           # Riverpod状态
        ├── services/            # API客户端
        ├── pages/               # 页面模块
        │   ├── auth/
        │   ├── files/
        │   ├── preview/
        │   ├── permissions/
        │   ├── audit/
        │   ├── ip/              # 讲师IP（阶段二）
        │   ├── marketing/       # 市场部（阶段三）
        │   ├── bidding/         # 招投标（阶段三）
        │   ├── pm/              # 项目管理（阶段四）
        │   ├── hr/              # HR（阶段四）
        │   └── finance/         # 财务（阶段四）
        └── widgets/             # 可复用组件
```

## 分阶段交付

| 阶段 | 内容 | 状态 | 模型 | API | 前端页面 | E2E |
|------|------|------|------|-----|---------|-----|
| 一 | 基础设施 + Flutter骨架 + 权限文件预览 | ✅ 完成 | 5 | 25+ | 8 | — |
| 二 | 讲师IP（AI文案生成 + HTML预览） | ✅ 部分 | 3 | 8 | 3 | — |
| 三 | 市场部 + 招投标 | ✅ 完成 | 17 | 34 | 20 | 54/54 |
| 四 | 项目管理 + HR + 财务 | ✅ 完成 | 10 | 36 | 14 | 48/48 |
| 五 | 联调 + 安全 + 三端打包分发 + 部署 | 🔄 进行中 | — | — | — | — |

### 阶段五新增功能

| 功能 | 说明 |
|------|------|
| ES 语义搜索 | BM25 + DeepSeek embedding (768维) + RRF 混合排序，覆盖全局+7模块搜索 |
| 财务升级 | 发票(Payment+Invoice 合同到收款链路) + 预算管控(部门/项目两级) + Dashboard(12月趋势图) |
| HR Dashboard | KPI卡片 + 饼图 + 响应式布局 |

### 阶段四模块一览

| 模块 | 模型 | 亮点功能 |
|------|------|---------|
| 项目管理 | PmProject, VisitLog, Courseware, ProjectReport | 项目台账 + 走访日志 + LLM项目报告生成 + 课件管理 |
| HR | Employee, Resume, Approval | 员工档案 + 简历上传(PDF/DOCX) + LLM智能匹配 + 审批流 |
| 财务 | Settlement, Expense, Voucher, Invoice, Payment, Budget | 结算+报销审批+凭证归档+发票+收款+预算管控 |

## 关键约束

- 私有化部署，数据不出企业
- 移动端为原生App（.apk），PC端为原生桌面程序（.exe）
- 预算优先，善用开源方案降本
- 开发期 LLM 使用 DeepSeek API，生产可切换本地 Qwen2.5 14B

## 报告

完整可行性分析与分阶段SRS报告见：`AI场景建设系统_可行性分析与分阶段SRS报告.pdf`
