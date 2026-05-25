# CHANGELOG — 开发日志

## 2026-05-25 — OnlyOffice → LibreOffice + 下载修复

### 变更

**预览重构** — 移除 OnlyOffice Docker 容器，改用 LibreOffice headless 本地转换：
- 新增 `backend/app/services/converter.py`：LibreOffice headless 子进程封装，自动查找 soffice.exe
- 修改 `backend/app/api/preview.py`：
  - Office MIME（.doc/.docx/.xls/.xlsx/.ppt/.pptx）→ 取文件 → LibreOffice 转 PDF → 上传临时 PDF 到 MinIO → 返回预签名 URL
  - 新增 `POST /preview/close/{id}` 端点，退出预览时删除临时 PDF
  - 移除 `onlyoffice_config` 端点
  - 新增扩展名兜底检测：MIME 不准时按 `.doc`/`.xlsx` 等扩展名识别
- 修改 `frontend/lib/pages/preview/preview_page.dart`：
  - 移除 OnlyOffice WebView 控制器和 HTML 注入
  - Office 文件统一走 PDF WebView 预览
  - dispose 时调 `/preview/close/{id}` 清理临时 PDF

**下载修复** — 之前菜单里有"下载"选项但没接线：
- 修改 `frontend/lib/pages/files/file_list_page.dart`：新增 `_downloadFile()` 方法
  - 弹出原生文件夹选择对话框 → 用户自选路径 → `dio.download()` 下载到该目录
- `onSelected` 补上 `download` 分支

**配置清理**：
- `docker-compose.yml`：移除 OnlyOffice 服务 + volumes
- `backend/app/config.py`：移除 `ONLYOFFICE_URL`

### 验证

- 6 种 Office 格式全部端到端测试通过：`.doc` / `.docx` / `.xls` / `.xlsx` / `.ppt` / `.pptx`
- 转换出的 PDF 均可正常访问（HTTP 200）
- 临时 PDF 清理端点正常
- Flutter 静态分析 0 issues
- Windows .exe 编译成功

### 前置条件变更

- 新增依赖：LibreOffice（`winget install TheDocumentFoundation.LibreOffice`）
- 移除依赖：OnlyOffice Docker 容器（不再需要）

---

## 2026-05-25（续）— 保密级别 + 用户管理 + 媒体预览

### 变更

**保密级别自动授权** — 替代手动 ACL 权限授予：
- `backend/app/config.py`：新增 `ROLE_CLEARANCE` 映射（admin=3, dept_manager=2, project_manager=1, general=0）
- `backend/app/models/models.py`：File 模型新增 `confidentiality_level` 字段（0-3，默认0）
- `backend/app/services/permission_checker.py`：
  - admin 提前放行
  - owner 豁免（用户始终能看自己上传的文件）
  - 保密级别检查：`user_level >= file_level` → 自动通过
  - 以上都不匹配才走显式 ACL 检查（兜底）
- `backend/app/api/files.py`：
  - 上传端点接受 `confidentiality_level` 参数（0-3）
  - 新增 `PATCH /files/{file_id}/level`（admin 修改文档级别）
  - 列表端点返回 `confidentiality_level` 和 `uploaded_by`
- `backend/init.sql`：`ALTER TABLE files ADD COLUMN confidentiality_level INTEGER DEFAULT 0`
- Flutter 文件列表页：
  - 每行显示保密级别标签（公开/内部/机密/绝密，绿/蓝/橙/红）
  - admin 点击标签弹出下拉菜单修改级别
  - 文件下载功能（`FilePicker.getDirectoryPath` 选择保存路径）

**用户管理** — admin 可管理所有用户和角色：
- `backend/app/api/auth.py`：
  - 新增 `GET /auth/users`（admin only，列出所有用户）
  - 新增 `PATCH /auth/users/{user_id}/role`（admin 修改用户角色）
- Flutter：新增用户管理页 `users_page.dart`（/users 路由 + 导航栏入口）
- 角色名称中文化：admin=管理员, dept_manager=部门经理, project_manager=项目经理, general=普通用户

**媒体预览修复** — 图片/音频/视频端到端测试和修复：
- `backend/app/api/preview.py`：
  - 新增 `MIME_BY_EXT` 字典 + `_guess_mime()` 函数，扩展名兜底检测
  - 解决 ffmpeg 生成的文件 MIME 为 `application/octet-stream` 的问题
- `frontend/lib/pages/preview/preview_page.dart`：
  - 音频/视频从 `video_player` 改为 WebView + HTML5 标签（Edge WebView2 内核）
  - 解决 `video_player` Windows 端对预签名 URL 支持问题
  - 自带完整播放控件（播放/暂停/进度条/音量）

**UI 优化**：
- 移除手动 ACL 权限管理页（被保密级别自动授权替代）
- 导航栏从 4 个 tab 缩减为 3 个：文件、审计、用户
- 关闭 DEBUG banner（`debugShowCheckedModeBanner: false`）
- 权限搜索改为模糊搜索（`GET /permissions/search?q=`，ILIKE 匹配文件名/用户/角色）

### 验证

- 文档保密级别端到端测试：testuser(general/0) 被级别2文件拦截 → 提升至 project_manager(1) → 可访问级别1，仍被级别2拦截
- 图片/音频/视频上传 + 预览 + 下载全部通过，文件完整性校验通过
- Flutter 静态分析 0 issues
- Windows .exe 编译 + 运行正常
