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
