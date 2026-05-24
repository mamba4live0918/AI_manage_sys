# 公司AI场景建设管理系统

全链路AI赋能管理平台，一套 Flutter 代码编译 **Windows .exe / iOS .ipa / Android .apk / Web** 四端，FastAPI 后端提供 REST API。覆盖市场部、招投标合同中心、项目管理中台、HR、财务五大业务域 + 讲师IP专属子系统 + 全系统权限化文件预览。

## 技术栈

```
Flutter 3.x (Riverpod)  ←→  FastAPI 0.115  ←→  PostgreSQL 16
     ↕ 四端编译              ↕ async            Redis 7
  .exe .ipa .apk Web      REST API            MinIO
                                               OnlyOffice Docs
                                               Qwen2.5 14B (LLM)
                                               GPT-SoVITS (声音克隆)
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
│       ├── api/                 # 路由
│       │   ├── auth.py          # 注册/登录
│       │   ├── files.py         # 文件管理
│       │   ├── preview.py       # 预览/下载
│       │   ├── permissions.py   # 权限配置
│       │   └── audit.py         # 审计日志
│       └── services/            # 业务逻辑
│           ├── storage.py       # MinIO
│           ├── permission_checker.py  # ACL引擎
│           └── audit.py         # 审计写入
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

| 阶段 | 内容 | 周期 | 累计需求 |
|------|------|------|---------|
| 一 | 基础设施 + Flutter骨架 + 权限文件预览 | 5-6周 | 7 |
| 二 | 讲师IP（文案/声音/数字人/短视频） | 4-5周 | 12 |
| 三 | 市场部 + 招投标 | 5-6周 | 21 |
| 四 | 项目管理 + HR + 财务 | 5-6周 | 35 |
| 五 | 联调 + 安全 + 四端打包分发 + 部署 | 3-4周 | 51 |

## 关键约束

- 私有化部署，数据不出企业
- 移动端为原生App（.ipa/.apk），PC端为原生桌面程序（.exe）
- 数字人克隆需采购厂商私有化授权（约10-20万/年）
- 预算优先，善用开源方案降本

## 报告

完整可行性分析与分阶段SRS报告见：`AI场景建设系统_可行性分析与分阶段SRS报告.pdf`
