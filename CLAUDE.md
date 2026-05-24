# CLAUDE.md — AI助手项目上下文

## 项目概述

公司全链路AI赋能管理系统 — Flutter全端（Windows .exe / iOS .ipa / Android .apk / Web）+ FastAPI后端。覆盖市场部、招投标、项目管理、HR、财务五大业务域 + 讲师IP子系统 + 全系统权限化文件预览。

**开发模式**：一人+AI辅助编程（Claude Code / Cursor）
**总工期**：22-27周（约6-7个月），分5个阶段交付
**部署环境**：企业私有云/混合云，数据不出企业

## 技术栈

| 层 | 选型 | 说明 |
|----|------|------|
| 前端 | Flutter 3.x + Dart | 一套代码四端编译 |
| 状态管理 | Riverpod 2.x | 编译时安全 |
| HTTP | Dio | 拦截器 + JWT自动注入 |
| 后端 | Python FastAPI 0.115+ | async/await |
| ORM | SQLAlchemy 2.0 | async session |
| 数据库 | PostgreSQL 16 | UUID + JSONB |
| 缓存 | Redis 7 | Token黑名单 + 缓存 |
| 文件存储 | MinIO | S3兼容，私有部署 |
| 文档预览 | OnlyOffice Docs CE | 私有化部署 |
| AI推理 | Qwen2.5 14B (私有) | OpenAI兼容API |
| 声音克隆 | GPT-SoVITS | 私有部署 |
| 数字人 | 厂商SDK（待定） | 科大讯飞/硅基智能/商汤 |
| 部署 | Docker Compose | 一键启动全基础设施 |

## 项目结构

```
AI_manage_sys/
├── CLAUDE.md                    # 本文件
├── README.md                    # 人类可读文档
├── TODO.md                      # 全项目任务清单
├── docker-compose.yml           # PostgreSQL + Redis + MinIO + OnlyOffice
├── docs/
│   └── SRS.md                   # 原始需求文档
├── backend/
│   ├── requirements.txt
│   ├── init.sql
│   └── app/
│       ├── main.py
│       ├── config.py
│       ├── database.py
│       ├── security.py
│       ├── models/
│       ├── api/                 # auth/files/preview/permissions/audit
│       └── services/            # storage/permission_checker/audit
└── frontend/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── app.dart             # 路由 + MaterialApp
        ├── config/              # 环境配置
        ├── models/              # 数据模型
        ├── providers/           # Riverpod providers
        ├── services/            # API client (Dio)
        ├── pages/               # 页面
        │   ├── auth/            # 登录
        │   ├── files/           # 文件列表
        │   ├── preview/         # 预览页
        │   ├── permissions/     # 权限配置
        │   ├── audit/           # 审计日志
        │   ├── ip/              # 讲师IP（阶段二）
        │   ├── marketing/       # 市场部（阶段三）
        │   ├── bidding/         # 招投标（阶段三）
        │   ├── pm/              # 项目管理（阶段四）
        │   ├── hr/              # HR（阶段四）
        │   └── finance/         # 财务（阶段四）
        └── widgets/             # 可复用组件（水印/文件图标/权限Tag）
```

## 编码规范

### 后端 (Python/FastAPI)
- 所有API返回JSON，使用Pydantic模型序列化
- 异步优先（async def + await），除非确实不需要
- 数据库操作使用SQLAlchemy 2.0 async session
- 权限校验统一走 `services/permission_checker.py` 的5级ACL
- 所有预览/下载/上传/删除操作调用 `services/audit.py` 记录日志
- 不写超过一行的注释，除非WHY不显而易见

### 前端 (Flutter/Dart)
- 使用Riverpod进行状态管理，避免StatefulWidget
- 所有API调用统一走 `services/api_client.dart`（Dio单例）
- Material Design 3，使用 `useMaterial3: true`
- 响应式布局先行：根据屏幕宽度自动切换布局（桌面侧边栏 vs 手机底部Tab）
- 移动端原生能力通过 `image_picker`、`record`、`flutter_local_notifications` 等插件调用
- 四端差异通过 `Platform.isWindows` / `Platform.isIOS` / `Platform.isAndroid` 处理

### 通用
- 禁止硬编码URL、密钥等敏感信息，统一走config
- 每个阶段完成后打git tag（phase-1, phase-2...）
- 提交信息格式：`[阶段] 简短描述`

## 五阶段交付计划

| 阶段 | 内容 | 周期 |
|------|------|------|
| 阶段一 | 通用基础设施 + Flutter四端骨架 + 权限文件预览（SRS 3.1） | 5-6周 |
| 阶段二 | 讲师IP子系统（SRS 3.5） | 4-5周 |
| 阶段三 | 市场部 + 招投标（SRS 3.2） | 5-6周 |
| 阶段四 | 项目管理 + HR + 财务（SRS 3.3 + 3.4） | 5-6周 |
| 阶段五 | 联调 + 安全 + 四端打包分发 + 私有化部署 | 3-4周 |

## 当前状态

**阶段一进行中** — 初始搭建

## 关键约束

1. 私有化部署，数据不出企业
2. 移动端必须是可安装的App（.ipa / .apk），不是网页
3. PC端必须是可安装的桌面程序（.exe），不是浏览器网页
4. 预算优先，善用开源和第三方服务降本
5. 数字人克隆需采购厂商私有化授权（约10-20万/年）
6. 声音克隆使用开源方案（GPT-SoVITS），视频合成用ffmpeg管道
