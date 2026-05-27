# TODO — 全系统AI场景建设项目任务清单

> 开发模式：一人+AI | 总工期：22-27周 | 分5阶段交付 | Flutter全端 + FastAPI后端

---

## 阶段一：通用基础设施 + 权限文件预览（5-6周）

### 迭代1.1 — 项目骨架（1周）

- [x] 初始化Flutter项目（`flutter create`），配置四端入口
- [x] 配置Riverpod + Dio + GoRouter
- [x] 创建项目目录结构（pages/widgets/providers/services/models/config）
- [x] 创建FastAPI项目骨架，配置CORS + 路由注册
- [x] 编写docker-compose.yml（PostgreSQL + Redis + MinIO）
- [x] 编写数据库初始化SQL（用户表、文件表、权限表、审计日志表 + 索引）
- [x] 配置Alembic数据库迁移
- [x] 四端Hello World验证（Windows exe / Android Emulator / Chrome）~iOS暂缓~

### 迭代1.2 — 用户认证 + RBAC（1周）

- [x] 后端：用户注册API + 登录API（JWT）
- [x] 后端：bcrypt密码哈希 + Token生成/验证
- [x] 后端：4级角色模型（admin / dept_manager / project_manager / general）
- [x] 后端：get_current_user 依赖注入 + require_roles 守卫
- [x] 后端：用户管理CRUD（仅admin）
- [x] Flutter：登录页面（用户名+密码 → JWT存储）
- [x] Flutter：Dio拦截器（请求自动注入Token，401自动跳转登录）
- [x] Flutter：AuthProvider（Riverpod，管理登录状态）
- [x] Flutter：路由守卫（未登录 → /login）
- [x] Flutter：PC端侧边栏导航 / 移动端底部Tab导航

### 迭代1.3 — 文件管理 + 存储（1.5周）

- [x] 后端：MinIO服务集成（初始化bucket + 策略配置）
- [x] 后端：文件上传API（multipart，自动MIME识别，存储到MinIO）
- [x] 后端：文件列表API（分页 + 按目录筛选 + 排序）
- [x] 后端：创建文件夹API
- [x] 后端：删除文件/文件夹API
- [x] Flutter：文件列表页面（ListView自适应桌面/移动端）
- [x] Flutter：文件类型图标组件（文档/图片/音频/视频/文件夹）
- [x] Flutter：面包屑导航 + 多级目录浏览
- [x] Flutter：文件上传组件（文件选择器）
- [ ] Flutter：移动端原生拍照上传（image_picker）~阶段二再做~
- [x] Flutter：删除确认对话框

### 迭代1.4 — 文档预览（1周）

- [x] ~~Docker：OnlyOffice Document Server部署~~ → **LibreOffice headless**（更轻量）
- [x] 后端：Office文件转PDF API（LibreOffice CLI）
- [x] 后端：临时PDF上传MinIO + 预签名URL返回
- [x] 后端：预览关闭清理API（POST /preview/close）
- [x] Flutter：PDF WebView预览（webview_windows）
- [x] Flutter：6种Office格式支持（.doc/.docx/.xls/.xlsx/.ppt/.pptx）

### 迭代1.5 — 媒体预览 + 水印（0.5周）

- [x] Flutter：图片预览（InteractiveViewer + 手势缩放）
- [x] Flutter：音频播放（HTML5 Audio via WebView）
- [x] Flutter：视频播放（HTML5 Video via WebView）
- [x] Flutter：后端MIME扩展名兜底检测（_guess_mime）
- [x] Flutter：Canvas动态水印组件（用户名+部门+日期，平铺覆盖）
- [x] Flutter：所有预览页叠加水印组件
- [ ] Flutter：可选禁止截屏 ~低优先级~

### 迭代1.6 — 权限系统（1.5周）

- [x] 后端：Permission模型（user/role/dept/project → resource → preview/download/edit）
- [x] 后端：5级ACL权限检查引擎 → **升级为保密级别自动授权**
- [x] 后端：保密级别模型（0公开/1内部/2机密/3绝密）+ 角色查看级别映射
- [x] 后端：owner豁免（用户始终能看自己上传的文件）
- [x] 后端：下载API（独立鉴权）
- [x] Flutter：保密级别标签显示（公开/内部/机密/绝密，颜色区分）
- [x] Flutter：admin点击标签修改保密级别
- [x] ~~权限配置页面~~ → 被保密级别自动授权替代，已移除
- [x] Flutter：文件下载（选择保存文件夹）

### 迭代1.7 — 审计日志（0.5周）

- [x] 后端：审计日志写入服务（preview/download/upload/delete/permission_change）
- [x] 后端：审计日志分页查询API（按用户/操作类型/时间范围筛选）
- [x] 后端：所有敏感操作调用审计服务记录
- [x] Flutter：审计日志查询页面（列表 + 筛选 + 分页）
- [x] Flutter：管理员侧边栏入口

### 阶段一额外完成

- [x] 用户管理页面（admin查看所有用户 + 修改角色）
- [x] 文件下载功能（自定义保存路径）
- [x] 模糊搜索（权限搜索 → 已随权限页移除，搜索 API 保留）
- [x] DEBUG banner 关闭

### 阶段一检查点

- [x] Windows .exe 编译通过
- [ ] Android .apk 编译验证 ~需要 Android SDK~
- [ ] iOS ~暂缓~
- [x] 用户注册 → 登录 → 上传文件 → 创建目录
- [x] Word/Excel/PPT/PDF预览 + 水印
- [x] 图片/音频/视频预览 + 水印
- [x] 保密级别自动授权（替代手动ACL）
- [x] 审计日志完整记录
- [ ] git tag: `phase-1-complete`

---

## 阶段二：讲师IP子系统（4-5周）

### 迭代2.1 — LLM文案生成（1-1.5周）

- [x] 后端：OpenAI兼容API封装（DeepSeek，config切换）
- [x] 后端：文案模板模型（公众号/朋友圈/小红书/抖音等，模板变量 + 提示词）
- [x] 后端：模板CRUD API
- [x] 后端：文案生成API（模板+参数 → LLM → 返回文案）
- [x] 后端：历史记录API（列表/详情/编辑/删除）
- [x] Flutter：文案生成页面（模板选择 → 参数填写 → 一键生成 → 二次编辑）
- [x] Flutter：HTML预览切换（Markdown/HTML双视图）
- [ ] 后端：Qwen2.5 14B私有化部署（Docker + GPU直通）~暂缓~
- [ ] Flutter：讲师素材库页面（CRUD，按讲师隔离）~暂缓~

### 迭代2.2 — 声音克隆（1-1.5周）⏭️ 跳过

### 迭代2.3 — 数字人 + 短视频合成（1.5周）⏭️ 跳过

### 阶段二检查点

- [x] 文案：选择模板 → 输入关键词 → 一键生成营销文案
- [ ] git tag: `phase-2-partial`（仅文案生成）

---

## 阶段三：前端业务模块 ✅ 已完成

> **实际完成**：17 模型 + 34 端点 + 20 前端页面，E2E 54/54。ES 全文检索 → 改用 SQL ILIKE/LIKE，图表 → 文本+LLM 替代。

### 迭代3.1 — 市场部-客户管理 + 方案生成 ✅

- [x] 后端：客户模型（资料/行为事件/满意度）
- [x] 后端：客户CRUD API + 附件上传
- [x] 后端：行为事件记录API（时间轴）
- [x] 后端：满意度评分API + 趋势计算
- [x] 后端：流失预警API（阈值配置 + 自动通知）
- [x] 后端：需求预测API（LLM分析行为数据 → 预测报告）
- [x] 后端：营销方案生成API（模板+客户画像 → LLM）
- [x] Flutter：客户列表/详情/编辑页面
- [x] Flutter：行为事件时间轴组件
- [x] Flutter：满意度仪表盘
- [x] Flutter：流失预警配置页
- [x] Flutter：需求预测报告页
- [x] Flutter：营销方案生成页
- [x] 所有附件接入通用预览

### 迭代3.2 — 市场部-项目跟进 + 社群运营 ✅

- [x] 后端：项目资料汇总API
- [x] 后端：简报生成API（LLM多文档摘要）
- [x] 后端：社群活跃度API
- [x] 后端：RAG知识库 + 智能问答API（LLM语义匹配）
- [x] Flutter：项目资料时间线视图
- [x] Flutter：简报生成 + 预览页
- [x] Flutter：社群分析仪表盘
- [x] Flutter：智能问答聊天界面
- [x] 所有文件接入通用预览

### 迭代3.3 — 招投标合同中心 ✅

- [x] 后端：合同模板模型 + CRUD API
- [x] 后端：合同生成API（模板+参数 → LLM）
- [x] 后端：合同版本管理API（归档 + 差异对比）
- [x] 后端：知识库目录模型 + 文档上传
- [x] ~~Elasticsearch~~ → SQL ILIKE + LLM 语义搜索
- [x] 后端：案例相似度推荐API
- [x] 后端：招投标流程阶段管理API
- [x] 后端：供应商师资模型 + 标签检索API
- [x] 后端：课程智能匹配API
- [x] Flutter：合同模板管理页
- [x] Flutter：合同生成页
- [x] Flutter：版本对比视图
- [x] Flutter：知识库搜索页
- [x] Flutter：供应商搜索 + 详情页
- [x] Flutter：课程匹配结果页
- [x] 所有文件接入通用预览

### 阶段三检查点

- [x] 市场部：客户管理 → 方案生成 → 项目跟进 → 社群运营全流程
- [x] 招投标：合同生成 → 版本归档 → 知识库检索 → 供应商匹配
- [x] Windows .exe 编译通过
- [x] E2E: 54/54 全部通过
- [ ] git tag: `phase-3-complete`

---

## 阶段四：中台 + 后端模块 ✅ 已完成

> **实际完成**：10 模型 + 36 端点 + 14 前端页面，E2E 48/48。简化：无 OCR（改 PDF/DOCX 文本提取）、无审批流引擎（改单步审批）、无图表/日历组件（下一版补）。

### 迭代4.1 — 项目管理-方案 + 过程管理 ✅

- [x] 后端：项目CRUD API（台账 + 阶段筛选）
- [x] 后端：走访日志API（文本记录）
- [x] 后端：LLM项目报告生成API
- [x] Flutter：项目列表/详情页
- [x] Flutter：走访日志页
- [ ] 后端：行事历 + 日历视图（TableCalendar）~下一版~
- [ ] 后端：AI点评生成 ~下一版~
- [ ] 后端：分析报表图表（fl_chart）~下一版~
- [ ] 后端：录音上传 + OCR ~下一版~

### 迭代4.2 — 项目管理-课件 + 评估 + 结算 ✅

- [x] 后端：课件管理API（CRUD + 项目筛选）
- [x] Flutter：课件管理页
- [ ] ~~后端：课件生成（知识库 → LLM → PPT/PDF）~~ → 下一版
- [ ] ~~后端：项目总结报告（全量材料 → LLM）~~ → 简化走4.1报告
- [ ] ~~后端：客户反馈收集~~ → 市场部已有满意度

### 迭代4.3 — 人力资源 ✅

- [x] 后端：简历上传API（PDF/DOCX + 文本提取）
- [x] 后端：AI简历匹配API（LLM评分）
- [x] 后端：员工档案模型 + CRUD API
- [x] 后端：审批API（请假/报销/转正，单步通过/驳回）
- [x] Flutter：简历上传 + 预览 + 匹配结果页
- [x] Flutter：员工档案管理 + 详情页
- [x] Flutter：审批列表 + 发起 + 审批页
- [ ] ~~后端：审批流引擎（多级流转）~~ → 简化为单步审批
- [ ] ~~后端：面试排期~~ → 下一版
- [ ] ~~后端：师资管理库~~ → 招投标已有供应商师资

### 迭代4.4 — 财务中心 ✅

- [x] 后端：结算CRUD API（状态流转 + 项目关联）
- [x] 后端：费用报销API（创建 + 审批）
- [x] 后端：凭证归档API（CRUD + 结算关联）
- [x] Flutter：结算列表 + 创建 + 详情页
- [x] Flutter：费用报销页（创建 + 分类筛选 + 审批）
- [x] Flutter：凭证管理页
- [ ] ~~后端：凭证文件上传~~ → 当前为文本描述

### 阶段四检查点

- [x] 全链路数据流：市场/招投标 → 项目管理 → HR/财务
- [x] 审批功能正常（单步 approve/reject）
- [x] 结算数据流正确
- [x] Windows .exe 编译通过
- [x] E2E: 48/48 全部通过
- [x] Phase 3 回归: 54/54 全部通过
- [ ] git tag: `phase-4-complete`

---

## 阶段五：联调 + 部署 + 上线（3-4周）

### 迭代5.1 — 系统联调（1周）

- [ ] 前端-中台数据同步接口联调
- [ ] 中台-财务/人力数据流转联调
- [ ] 全模块权限校验一致性测试
- [ ] 全模块预览流程端到端验证
- [ ] 四端UI/UX一致性检查
- [ ] 51个需求点逐条验收 + 测试清单
- [ ] OA/CRM系统对接（预留适配层）

### 迭代5.2 — 性能 + 安全（1-1.5周）

- [ ] AI生成响应时间压测（JMeter，目标≤10s）
- [ ] 知识库检索并发压测（50用户，≤2s）
- [ ] 音视频克隆时长测试（目标≤30s）
- [ ] 文档/图片/视频预览加载速度测试
- [ ] TLS传输加密验证
- [ ] AES-256存储加密验证
- [ ] 审计日志完整性抽查
- [ ] 克隆合规授权校验验证
- [ ] Windows 10/11 兼容性测试
- [ ] iOS 15+ / Android 10+ 兼容性测试
- [ ] Chrome/Edge 兼容性测试
- [ ] 主流文件格式预览兼容性测试

### 迭代5.3 — 四端打包分发（0.5-1周）

- [ ] Windows .exe 签名 + Inno Setup 安装包
- [ ] Android .apk 签名
- [ ] iOS .ipa 企业证书签名 + 分发plist
- [ ] Web 构建 + Nginx部署配置
- [ ] 安装说明文档（二维码扫码下载）

### 迭代5.4 — 私有化部署（1周）

- [ ] 生产环境部署架构图
- [ ] Docker镜像构建（backend + 各服务）
- [ ] docker-compose.prod.yml
- [ ] Nginx反向代理配置
- [ ] SSL证书配置
- [ ] 数据库备份脚本（pg_dump + cron）
- [ ] MinIO备份策略
- [ ] 系统监控配置（Prometheus + Grafana 可选）
- [ ] 部署安装手册
- [ ] 运维手册（启动/停止/备份/恢复/日志查看/故障排查）
- [ ] 管理员培训（权限配置/用户管理/审计操作）
- [ ] 系统交接确认书

### 阶段五检查点

- [ ] 51/51 需求点全部验收通过
- [ ] 四端安装包就绪，分发测试通过
- [ ] 性能指标全部达标
- [ ] 安全检查全部通过
- [ ] 部署文档完整
- [ ] 系统上线运行
- [ ] git tag: `phase-5-complete` | `v1.0.0`

---

## 全局检查清单

- [ ] 所有git commit遵循 `[阶段] 简短描述` 格式
- [ ] 敏感信息零硬编码（全部走.env/config）
- [ ] 每个阶段完成后更新CLAUDE.md的"当前状态"
- [ ] 每个阶段完成后打git tag
- [ ] 关键决策记录在CLAUDE.md或commit信息中
