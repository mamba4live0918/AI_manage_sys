# CLAUDE.md — AI助手项目上下文

## 项目概述

公司全链路AI赋能管理系统 — Flutter全端（Windows .exe / Android .apk / Web）+ FastAPI后端。覆盖市场部、招投标、项目管理、HR、财务五大业务域 + 讲师IP子系统 + 全系统权限化文件预览。

**开发模式**：一人+AI辅助编程（Claude Code / Cursor）
**总工期**：22-27周（约6-7个月），分5个阶段交付
**部署环境**：企业私有云/混合云，数据不出企业
**当前平台**：Windows .exe + Android .apk + Web（iOS 暂缓，无开发者账号）

## 技术栈

| 层 | 选型 | 版本 | 说明 |
|----|------|------|------|
| 前端 | Flutter + Dart | 3.44 / 3.12 | 一套代码三端编译（Win/Android/Web） |
| 状态管理 | Riverpod | 2.6.x | 编译时安全 |
| HTTP | Dio | 5.9.x | 拦截器 + JWT自动注入 |
| 后端 | Python FastAPI | 0.115+ | async/await |
| ORM | SQLAlchemy | 2.0 | async session + asyncpg |
| 数据库 | PostgreSQL | 16-alpine | UUID + JSONB |
| 密码哈希 | bcrypt | **4.0.1** | 必须钉住版本，5.x 与 passlib 不兼容 |
| 缓存 | Redis | 7-alpine | Token黑名单 + 缓存 |
| 文件存储 | MinIO | latest | S3兼容，私有部署 |
| 文档预览 | LibreOffice headless | — | Office→PDF 临时转换 + PDF WebView 预览 |
| AI推理 | Qwen2.5 14B (私有) | — | OpenAI兼容API，开发期用 DeepSeek |
| 声音克隆 | GPT-SoVITS | — | 私有部署 |
| 数字人 | 厂商SDK（待定） | — | 科大讯飞/硅基智能/商汤 |
| 部署 | Docker Compose | v2 | 一键启动全基础设施 |

## 项目结构

```
AI_manage_sys/
├── CLAUDE.md                    # 本文件（AI上下文）
├── README.md                    # 人类可读文档
├── TODO.md                      # 全项目任务清单（170+任务，5阶段）
├── docker-compose.yml           # PostgreSQL:5433 + Redis:6379 + MinIO:9000
├── docs/
│   └── SRS.md                   # 原始需求文档（51条FR）
├── backend/
│   ├── requirements.txt         # Python依赖（bcrypt钉在4.0.1）
│   ├── init.sql                 # 建表SQL + 默认admin/admin123
│   ├── .env                     # 环境变量（不提交）
│   └── app/
│       ├── main.py              # FastAPI入口 + /health
│       ├── config.py            # Pydantic Settings（.env → 配置）
│       ├── database.py          # SQLAlchemy async engine + session
│       ├── security.py          # bcrypt + JWT + get_current_user + require_roles
│       ├── models/models.py     # User / File / Permission / AuditLog
│       ├── api/                 # auth / files / preview / permissions / audit（14个端点）
│       └── services/            # storage(MinIO) / permission_checker(5级ACL) / audit / llm / converter(LibreOffice)
└── frontend/
    ├── pubspec.yaml             # Flutter依赖声明
    ├── pubspec.lock             # 锁定版本
    ├── windows/                 # Windows桌面平台（CMake + runner）
    └── lib/
        ├── main.dart            # ProviderScope + 入口
        ├── app.dart             # GoRouter + MaterialApp.router + Material3
        ├── config/              # 环境配置（API base URL）
        ├── models/              # User数据模型
        ├── providers/           # auth_provider（Riverpod StateNotifier）
        ├── services/            # api_client.dart（Dio单例 + JWT拦截器 + 401跳转）
        ├── pages/
        │   ├── auth/            # login_page — 用户名+密码登录
        │   ├── files/           # file_list_page — 浏览/上传/删除/文件夹
        │   ├── preview/         # preview_page — PDF/视频/图片/音频 + 水印（Office→LibreOffice→PDF）
        │   ├── permissions/     # permissions_page — ACL授予/撤销/查询
        │   ├── audit/           # audit_log_page — 审计日志分页+筛选
        │   ├── ip/              # 讲师IP（阶段二）
        │   ├── marketing/       # 市场部（阶段三）
        │   ├── bidding/         # 招投标（阶段三）
        │   ├── pm/              # 项目管理（阶段四）
        │   ├── hr/              # HR（阶段四）
        │   └── finance/         # 财务（阶段四）
        └── widgets/             # watermark(Canvas水印) / responsive_scaffold(自适应布局)
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
- 使用Riverpod进行状态管理，避免StatefulWidget（简单页面可以用ConsumerStatefulWidget）
- 所有API调用统一走 `services/api_client.dart`（Dio单例）
- Material Design 3，使用 `useMaterial3: true`
- 响应式布局：`responsive_scaffold.dart` 根据屏幕宽度自动切换 NavigationRail（桌面） vs NavigationBar（移动端）
- 仅 Windows/Android/Web 三端，`Platform.isWindows` / `Platform.isAndroid` 做差异处理
- file_picker 使用 `withData: true` + `bytes` 属性（v8.x API）

### 通用
- 禁止硬编码URL、密钥等敏感信息，统一走 config/.env
- 每个阶段完成后打git tag（phase-1-complete, phase-2-complete...）
- 提交信息使用常规格式（`fix:` / `feat:` 等），不强制 `[阶段]` 前缀
- 所有 LLM 调用走 `services/llm/router.py` 的抽象层，切换模型只需改 .env

## 五阶段交付计划

| 阶段 | 内容 | 迭代数 | 周期 |
|------|------|--------|------|
| 阶段一 | 通用基础设施 + Flutter三端骨架 + 权限文件预览 | 1.1~1.7（7个迭代） | 5-6周 |
| 阶段二 | 讲师IP子系统（LLM文案+声音克隆+数字人+短视频） | 2.1~2.3 | 4-5周 |
| 阶段三 | 市场部（客户管理+方案生成+社群运营）+ 招投标 | 3.1~3.3 | 5-6周 |
| 阶段四 | 项目管理 + HR + 财务 | 4.1~4.4 | 5-6周 |
| 阶段五 | 联调 + 性能安全 + 三端打包分发 + 私有化部署 | 5.1~5.4 | 3-4周 |

## 当前状态

**阶段一 — 功能完成，收尾阶段**

### 已完成
- Docker 基础设施运行正常（PostgreSQL:5433 / Redis:6379 / MinIO:9000）
- 数据库 4 张表（users/files/permissions/audit_logs）+ 默认 admin 账号（admin/admin123）
- 20+ API 端点全部测试通过
- Flutter 静态分析 0 issues
- Windows .exe 编译成功
- LLM 抽象层就绪（config 切换 DeepSeek → Qwen2.5 14B）
- **保密级别自动授权**（替代手动 ACL）：4级保密 + 角色查看级别映射 + owner 豁免
- OnlyOffice 替换为 LibreOffice headless：Word/Excel/PPT 自动转 PDF 预览，退出清理
- 文件下载支持自定义路径（文件夹选择器）
- 后端扩展名兜底 MIME 检测（`_guess_mime()`：图片/音频/视频/Office 全覆盖）
- 6 种 Office 格式端到端验证通过（.doc/.docx/.xls/.xlsx/.ppt/.pptx）
- 图片/音频/视频上传 + 预览 + 下载端到端验证通过
- 用户管理页面（admin 查看用户列表 + 修改角色）
- 审计日志分页查询 + 筛选
- UI：iOS 风格侧边栏/底部栏（文件/审计/用户 3 tab）+ 深色/浅色主题切换
- 前端 Canvas 动态水印（用户名+部门+日期）

### 待完成
- Android .apk 编译验证（需要 Android SDK cmdline-tools）
- git tag: `phase-1-complete`

## 已知问题 & 注意事项

1. **bcrypt 必须钉在 4.0.1**：5.x 移除了 `__about__.__version__` 导致 passlib 1.7.4 不兼容
2. **Docker PostgreSQL 端口改为 5433**：本地有 Windows PostgreSQL 16 服务占用 5432，Docker 映射到 5433
3. **Flutter SDK 路径**：`C:\Users\Mamba4live\Downloads\flutter\`（未加入 PATH）
4. **VS BuildTools**：需要安装 "C++ ATL for v142" + "Windows 10 SDK 10.0.22621+" 才能编译 Windows
5. **Android 编译待配置**：需要 Android Studio 或 cmdline-tools
6. **LibreOffice 必须安装**：Office 文件预览依赖 LibreOffice headless 转 PDF，安装 `winget install TheDocumentFoundation.LibreOffice`

## 关键约束

1. 私有化部署，数据不出企业
2. 移动端必须是可安装的App（.apk），不是网页
3. PC端必须是可安装的桌面程序（.exe），不是浏览器网页
4. 预算优先，开发期用免费API（DeepSeek），生产切本地模型
5. 数字人克隆需采购厂商私有化授权（约10-20万/年）
6. 声音克隆使用开源方案（GPT-SoVITS），视频合成用ffmpeg管道
