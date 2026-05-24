#!/usr/bin/env python3
"""生成《开发阶段实施计划》PDF —— 面向一人+AI实际开发执行"""

import os
from datetime import datetime

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY
from reportlab.lib.colors import HexColor, black, white, grey
from reportlab.lib.units import mm
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    HRFlowable,
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

# ─── 字体 ─────────────────────────────────────────────────
FONT_DIR = "C:/Windows/Fonts"
pdfmetrics.registerFont(TTFont("SimHei", os.path.join(FONT_DIR, "simhei.ttf")))
pdfmetrics.registerFont(TTFont("SimSun", os.path.join(FONT_DIR, "simsun.ttc"), subfontIndex=0))
pdfmetrics.registerFont(TTFont("SimKai", os.path.join(FONT_DIR, "simkai.ttf")))

# ─── 颜色 ─────────────────────────────────────────────────
PRIMARY = HexColor("#1a56db")
DARK_BG = HexColor("#1e293b")
TABLE_HEADER = HexColor("#2563eb")
TABLE_ROW_ALT = HexColor("#f8fafc")
BORDER = HexColor("#cbd5e1")
GREEN = HexColor("#059669")
ORANGE = HexColor("#ea580c")
RED = HexColor("#dc2626")

# ─── 样式 ─────────────────────────────────────────────────
styles = getSampleStyleSheet()
styles.add(ParagraphStyle("CoverTitle", fontName="SimHei", fontSize=26, leading=36, alignment=TA_CENTER))
styles.add(ParagraphStyle("CoverSub", fontName="SimSun", fontSize=13, leading=20, alignment=TA_CENTER, textColor=grey))
styles.add(ParagraphStyle("Ch", fontName="SimHei", fontSize=19, leading=27, textColor=PRIMARY, spaceBefore=18, spaceAfter=12))
styles.add(ParagraphStyle("Sec", fontName="SimHei", fontSize=14, leading=20, textColor=DARK_BG, spaceBefore=14, spaceAfter=6))
styles.add(ParagraphStyle("SSec", fontName="SimHei", fontSize=11, leading=16, textColor=HexColor("#334155"), spaceBefore=8, spaceAfter=4))
styles.add(ParagraphStyle("Body", fontName="SimSun", fontSize=10, leading=17, alignment=TA_JUSTIFY, spaceBefore=2, spaceAfter=5, firstLineIndent=20))
styles.add(ParagraphStyle("BodyNI", fontName="SimSun", fontSize=10, leading=17, alignment=TA_JUSTIFY, spaceBefore=2, spaceAfter=5))
styles.add(ParagraphStyle("Cell", fontName="SimSun", fontSize=8.5, leading=13, alignment=TA_CENTER))
styles.add(ParagraphStyle("CellV", fontName="SimSun", fontSize=8.5, leading=13, alignment=TA_JUSTIFY))
styles.add(ParagraphStyle("CellB", fontName="SimHei", fontSize=8.5, leading=13, alignment=TA_CENTER))
styles.add(ParagraphStyle("Note", fontName="SimKai", fontSize=8, leading=12, textColor=grey, alignment=TA_CENTER))
styles.add(ParagraphStyle("Check", fontName="SimSun", fontSize=9.5, leading=16, leftIndent=12))

def H(l, t): return Paragraph(t, styles[l])
def B(t): return Paragraph(t, styles["Body"])
def BN(t): return Paragraph(t, styles["BodyNI"])
def S(h=6): return Spacer(1, h)
def HR(): return HRFlowable(width="100%", thickness=0.5, color=BORDER, spaceBefore=4, spaceAfter=4)

def make_table(headers, rows, col_widths, variant=False):
    cs = "CellV" if variant else "Cell"
    data = [[Paragraph(f"<b>{h}</b>", styles["CellB"]) for h in headers]]
    for row in rows:
        data.append([Paragraph(str(c), styles[cs]) if not isinstance(c, Paragraph) else c for c in row])
    if col_widths is None:
        col_widths = [460 / len(headers)] * len(headers)
    t = Table(data, colWidths=col_widths, repeatRows=1)
    cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "SimHei"),
        ("FONTSIZE", (0, 0), (-1, 0), 9),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 8),
        ("TOPPADDING", (0, 0), (-1, 0), 8),
        ("FONTNAME", (0, 1), (-1, -1), "SimSun"),
        ("FONTSIZE", (0, 1), (-1, -1), 8.5),
        ("TOPPADDING", (0, 1), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 1), (-1, -1), 5),
        ("GRID", (0, 0), (-1, -1), 0.4, BORDER),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]
    for i in range(1, len(data)):
        if i % 2 == 0:
            cmds.append(("BACKGROUND", (0, i), (-1, i), TABLE_ROW_ALT))
    t.setStyle(TableStyle(cmds))
    return t

def task_row(task_id, desc, priority, est):
    """生成任务行"""
    p_color = {"P0": RED, "P1": ORANGE, "P2": GREEN}.get(priority, black)
    return [
        Paragraph(task_id, styles["Cell"]),
        Paragraph(desc, styles["CellV"]),
        Paragraph(f'<font color="{p_color.hexval()}"><b>{priority}</b></font>', styles["Cell"]),
        Paragraph(est, styles["Cell"]),
    ]

def phase_checklist(title, items):
    """生成阶段检查清单"""
    result = [H("SSec", title)]
    for item in items:
        result.append(Paragraph(f"☐  {item}", styles["Check"]))
    return result

# ═══════════════════════════════════════════════════════════
output_path = "开发阶段实施计划.pdf"
doc = SimpleDocTemplate(output_path, pagesize=A4, leftMargin=20*mm, rightMargin=20*mm, topMargin=18*mm, bottomMargin=18*mm,
                        title="AI场景建设系统 — 开发阶段实施计划")
story = []

# ─── 封面 ────────────────────────────────────────────────
story.append(S(60))
story.append(H("CoverTitle", "公司AI场景建设系统"))
story.append(S(6))
story.append(H("CoverTitle", "开发阶段实施计划"))
story.append(S(16))
story.append(HRFlowable(width="55%", thickness=2, color=PRIMARY, spaceBefore=8, spaceAfter=8))
story.append(S(10))
story.append(H("CoverSub", "Flutter全端架构 · 一人+AI开发模式"))
story.append(H("CoverSub", "面向实际执行的开发路线图与任务分解"))
story.append(S(24))
story.append(H("CoverSub", f"版本：V1.0 | {datetime.now().strftime('%Y年%m月%d日')}"))
story.append(H("CoverSub", "密级：内部"))
story.append(PageBreak())

# ─── 1. 开发总览 ──────────────────────────────────────────
story.append(H("Ch", "一、开发总览"))
story.append(HR())

story.append(H("Sec", "1.1 技术架构"))
arch = [
    ["层", "选型", "说明"],
    ["前端", "Flutter 3.x + Riverpod + Dio", "一套Dart → Windows.exe/iOS.ipa/Android.apk/Web"],
    ["后端", "Python FastAPI 0.115+", "async/await，Pydantic类型安全"],
    ["数据库", "PostgreSQL 16 + Redis 7", "UUID主键+JSONB，Redis做Token黑名单"],
    ["文件存储", "MinIO（S3兼容）", "私有化部署，Range分片支持"],
    ["文档预览", "OnlyOffice Docs CE", "私有化部署，Word/Excel/PDF"],
    ["LLM（开发期）", "DeepSeek API（OpenAI兼容）", "免费/低成本，开发调试用"],
    ["LLM（生产期）", "Qwen2.5 14B 私有化部署", "通过vLLM提供OpenAI兼容API，改URL即切换"],
    ["声音克隆", "GPT-SoVITS", "私有化部署"],
    ["数字人", "厂商SDK（待采购）", "科大讯飞/硅基智能/商汤"],
    ["部署", "Docker Compose", "一键启动全部基础设施"],
]
story.append(make_table(["层", "选型", "说明"], arch, [70, 130, 260], variant=True))
story.append(Paragraph("表1.1　技术栈", styles["Note"]))

story.append(H("Sec", "1.2 LLM架构设计（关键决策）"))
story.append(B("开发阶段使用免费/低成本API（DeepSeek等），但通过统一的 BaseLLMProvider 抽象层封装。所有业务代码调用 get_llm().chat() 统一接口，不直接依赖任何特定厂商SDK。生产环境只需修改两个环境变量即可切换到本地部署模型："))
story.append(S(4))
llm_arch = [
    ["环境", "LLM_BASE_URL", "LLM_MODEL", "LLM_API_KEY", "月成本"],
    ["开发", "https://api.deepseek.com/v1", "deepseek-chat", "sk-xxx（免费额度）", "¥0"],
    ["开发备选", "https://api.groq.com/openai/v1", "llama-3.1-70b", "gsk_xxx（免费额度）", "¥0"],
    ["生产（本地）", "http://gpu-server:8000/v1", "qwen2.5-14b", "not-needed", "¥0（电费）"],
    ["生产（云端）", "https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus", "sk-xxx", "按量付费"],
]
story.append(make_table(["环境", "LLM_BASE_URL", "LLM_MODEL", "LLM_API_KEY", "月成本"], llm_arch, [65, 160, 80, 110, 55], variant=True))
story.append(Paragraph("表1.2　LLM后端切换方案（仅改环境变量，零代码改动）", styles["Note"]))
story.append(B("核心原则：所有AI调用走统一的 OpenAI兼容协议（/v1/chat/completions），这是行业事实标准——DeepSeek、Groq、vLLM、Ollama、阿里百炼、智谱GLM全部兼容。"))

story.append(H("Sec", "1.3 开发环境"))
env = [
    ["工具", "用途", "备注"],
    ["VS Code + Claude Code", "AI辅助编程", "本项目主力IDE"],
    ["Cursor", "AI辅助编程（备选）", "Claude 4.5 Sonnet"],
    ["Docker Desktop", "本地基础设施", "PostgreSQL/Redis/MinIO/OnlyOffice"],
    ["Flutter SDK 3.x", "前端开发+编译", "stable channel"],
    ["Android Studio", "Android模拟器", "移动端调试"],
    ["Xcode（仅macOS）", "iOS模拟器+签名", "iOS编译必需"],
    ["Python 3.12+", "后端开发", "venv虚拟环境"],
    ["Postman / Bruno", "API调试", "或直接用curl"],
    ["Git + GitHub", "版本管理", "每个阶段结束打tag"],
]
story.append(make_table(["工具", "用途", "备注"], env, [90, 110, 260], variant=True))
story.append(Paragraph("表1.3　开发环境清单", styles["Note"]))
story.append(PageBreak())

# ─── 2. 阶段一 ────────────────────────────────────────────
story.append(H("Ch", "二、阶段一：通用基础设施 + 权限文件预览（5-6周）"))
story.append(HR())
story.append(B("目标：搭建Flutter全端项目骨架 + FastAPI后端，实现全系统权限化页内文件预览的四端交付。"))

story.append(H("Sec", "2.1 迭代1.1 — 项目骨架（第1周）"))
t11 = [
    task_row("T1.1.1", "初始化Flutter项目，配置四端入口（windows/ios/android/web）", "P0", "1d"),
    task_row("T1.1.2", "配置Riverpod 2.x + Dio + GoRouter + Material3主题", "P0", "0.5d"),
    task_row("T1.1.3", "创建Flutter项目目录结构（pages/widgets/providers/services/models）", "P1", "0.5d"),
    task_row("T1.1.4", "创建FastAPI项目骨架，配置CORS+路由注册+异常处理", "P0", "0.5d"),
    task_row("T1.1.5", "编写docker-compose.yml（PostgreSQL 16+Redis 7+MinIO+OnlyOffice）", "P0", "0.5d"),
    task_row("T1.1.6", "编写数据库init.sql（users/files/permissions/audit_logs四表+索引）", "P0", "0.5d"),
    task_row("T1.1.7", "实现LLM抽象层：BaseLLMProvider + OpenAICompatibleProvider + Router", "P0", "1d"),
    task_row("T1.1.8", "四端Hello World验证（exe/build + iOS Sim + Android Emu + Chrome）", "P0", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t11, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表2.1　迭代1.1任务清单", styles["Note"]))

story.append(H("Sec", "2.2 迭代1.2 — 用户认证 + RBAC（第2周）"))
t12 = [
    task_row("T1.2.1", "后端：User模型 + 注册API + 登录API（bcrypt + JWT）", "P0", "1.5d"),
    task_row("T1.2.2", "后端：4级角色模型 + get_current_user依赖 + require_roles守卫", "P0", "1d"),
    task_row("T1.2.3", "后端：用户管理CRUD（admin权限）", "P1", "0.5d"),
    task_row("T1.2.4", "Flutter：登录页面 + AuthProvider(Riverpod) + Token持久化", "P0", "1d"),
    task_row("T1.2.5", "Flutter：Dio拦截器（自动注入JWT + 401→登录页）", "P0", "0.5d"),
    task_row("T1.2.6", "Flutter：响应式布局（PC侧边栏/平板底部Tab/手机抽屉菜单）", "P0", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t12, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表2.2　迭代1.2任务清单", styles["Note"]))

story.append(H("Sec", "2.3 迭代1.3 — 文件管理 + 存储（第2-3周）"))
t13 = [
    task_row("T1.3.1", "后端：MinIO服务集成（bucket创建+策略配置+预签名URL）", "P0", "1d"),
    task_row("T1.3.2", "后端：文件上传API（multipart + MIME识别 + MinIO存储）", "P0", "1d"),
    task_row("T1.3.3", "后端：文件列表API（分页+目录筛选+排序+搜索）", "P0", "0.5d"),
    task_row("T1.3.4", "后端：文件夹CRUD API + 删除（递归处理）", "P1", "0.5d"),
    task_row("T1.3.5", "Flutter：文件列表页面（GridView/ListView自适应）+ 文件图标组件", "P0", "1.5d"),
    task_row("T1.3.6", "Flutter：面包屑导航 + 多级目录浏览", "P1", "0.5d"),
    task_row("T1.3.7", "Flutter：上传组件（桌面拖拽/移动端拍照+相册+文件选择器）", "P0", "1d"),
    task_row("T1.3.8", "Flutter：删除确认 + 批量操作", "P2", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t13, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表2.3　迭代1.3任务清单", styles["Note"]))

story.append(H("Sec", "2.4 迭代1.4 — 文档预览（第3-4周）"))
t14 = [
    task_row("T1.4.1", "OnlyOffice Docker部署+健康检查+配置调优", "P0", "1d"),
    task_row("T1.4.2", "后端：OnlyOffice配置API（JWT签名+编辑器配置JSON）", "P0", "1d"),
    task_row("T1.4.3", "后端：OnlyOffice回调API（保存/关闭/强制保存事件）", "P0", "1d"),
    task_row("T1.4.4", "Flutter：OnlyOffice WebView集成（webview_windows/ios/android）", "P0", "2d"),
    task_row("T1.4.5", "Flutter：预览页全屏模式 + 退出+返回导航", "P1", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t14, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表2.4　迭代1.4任务清单", styles["Note"]))

story.append(H("Sec", "2.5 迭代1.5 — 媒体预览 + 水印（第4周）"))
t15 = [
    task_row("T1.5.1", "Flutter：图片预览器（InteractiveViewer+手势缩放+多图滑动）", "P0", "1d"),
    task_row("T1.5.2", "Flutter：音频播放器（just_audio+后台播放+进度控制）", "P1", "0.5d"),
    task_row("T1.5.3", "Flutter：视频播放器（video_player+全屏+手势音量/亮度）", "P0", "1d"),
    task_row("T1.5.4", "后端+Flutter：流式分片加载（Range请求头+206 Partial Content）", "P1", "1d"),
    task_row("T1.5.5", "Flutter：Canvas动态水印组件（用户名+部门+时间，平铺旋转）", "P0", "0.5d"),
    task_row("T1.5.6", "Flutter：所有预览页叠加水印 + 可选截屏防护(FLAG_SECURE)", "P0", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t15, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表2.5　迭代1.5任务清单", styles["Note"]))

story.append(H("Sec", "2.6 迭代1.6 — 权限系统（第4-5周）"))
t16 = [
    task_row("T1.6.1", "后端：Permission模型设计（user/role/dept/project→resource→action）", "P0", "1d"),
    task_row("T1.6.2", "后端：5级ACL权限检查引擎（用户→角色→部门→项目→父目录递归继承）", "P0", "1.5d"),
    task_row("T1.6.3", "后端：权限检验中间件（预览/下载API调用前自动执行）", "P0", "0.5d"),
    task_row("T1.6.4", "后端：权限授予/撤销/查询API", "P0", "1d"),
    task_row("T1.6.5", "后端：下载API（独立鉴权，仅授权用户）+ 流式下载", "P0", "0.5d"),
    task_row("T1.6.6", "Flutter：权限配置管理页（角色/用户/部门+资源树→授予权限）", "P0", "1.5d"),
    task_row("T1.6.7", "Flutter：文件列表权限Tag（可预览绿/可下载蓝/无权限灰）", "P1", "0.5d"),
    task_row("T1.6.8", "Flutter：无权限→拦截弹窗+提示；无下载→隐藏下载按钮", "P0", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t16, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表2.6　迭代1.6任务清单", styles["Note"]))

story.append(H("Sec", "2.7 迭代1.7 — 审计日志 + 阶段一收尾（第5-6周）"))
t17 = [
    task_row("T1.7.1", "后端：AuditLog服务（preview/download/upload/delete/permission_change）", "P0", "1d"),
    task_row("T1.7.2", "后端：审计日志分页查询API（用户/操作/时间/资源类型筛选）", "P0", "0.5d"),
    task_row("T1.7.3", "Flutter：审计日志查询页（Table+筛选+分页+导出）", "P1", "1d"),
    task_row("T1.7.4", "全系统敏感操作接入审计服务", "P0", "0.5d"),
    task_row("T1.7.5", "四端编译+基础功能回归测试", "P0", "1d"),
    task_row("T1.7.6", "阶段一完整功能走查 + bug修复 + git tag phase-1-complete", "P0", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t17, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表2.7　迭代1.7 + 收尾任务清单", styles["Note"]))
story.append(PageBreak())

# ─── 3. 阶段二 ────────────────────────────────────────────
story.append(H("Ch", "三、阶段二：讲师IP子系统（4-5周）"))
story.append(HR())
story.append(B("目标：在阶段一基础上构建讲师IP工具。移动端调用原生相机/麦克风采集素材，PC端负责后台管理和批量生产。"))

story.append(H("Sec", "3.1 迭代2.1 — LLM文案生成（第1-1.5周）"))
t21 = [
    task_row("T2.1.1", "Qwen2.5 14B Docker私有化部署（NVIDIA GPU直通+健康检查）", "P1", "1d"),
    task_row("T2.1.2", "LLM服务API封装：OpenAI兼容 /v1/chat/completions 端点", "P0", "0.5d"),
    task_row("T2.1.3", "文案模板模型 + 提示词管理（公众号/朋友圈/短视频脚本模板）", "P0", "1d"),
    task_row("T2.1.4", "文案生成API：模板+参数→LLM→返回文案（复用LLM抽象层）", "P0", "0.5d"),
    task_row("T2.1.5", "Flutter文案生成页（模板选择→参数填写→一键生成→编辑→保存）", "P0", "1.5d"),
    task_row("T2.1.6", "Flutter讲师素材库（CRUD+按讲师隔离+预览）", "P0", "1d"),
    task_row("T2.1.7", "生成文案接入阶段一通用预览服务（水印+权限）", "P1", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t21, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表3.1　迭代2.1任务清单", styles["Note"]))

story.append(H("Sec", "3.2 迭代2.2 — 声音克隆（第1.5-3周）"))
t22 = [
    task_row("T2.2.1", "GPT-SoVITS Docker私有化部署（GPU直通）", "P0", "1d"),
    task_row("T2.2.2", "声音样本上传API（移动端录音→上传）", "P0", "0.5d"),
    task_row("T2.2.3", "声音克隆训练API（异步任务+状态轮询）", "P0", "1d"),
    task_row("T2.2.4", "语音合成API（文字→克隆语音，目标≤15s/30字）", "P0", "1d"),
    task_row("T2.2.5", "声音权限校验（讲师本人+管理员）", "P1", "0.5d"),
    task_row("T2.2.6", "合规授权API（克隆前强制确认+记录留存）", "P0", "0.5d"),
    task_row("T2.2.7", "Flutter移动端录音组件（record包，原生麦克风+波形显示）", "P0", "1d"),
    task_row("T2.2.8", "Flutter声音管理页（录音→上传→训练→试听）", "P0", "1d"),
    task_row("T2.2.9", "Flutter合规授权弹窗（克隆前确认+勾选协议）", "P0", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t22, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表3.2　迭代2.2任务清单", styles["Note"]))

story.append(H("Sec", "3.3 迭代2.3 — 数字人 + 短视频合成（第3-5周）"))
t23 = [
    task_row("T2.3.1", "数字人厂商选型确认（对比科大讯飞/硅基智能/商汤）→签合同→获取SDK", "P0", "2d"),
    task_row("T2.3.2", "数字人形象管理API（移动端拍照→厂商训练→返回形象ID）", "P0", "1d"),
    task_row("T2.3.3", "数字人口播API（文本+声音+形象→口播视频）", "P0", "1.5d"),
    task_row("T2.3.4", "ffmpeg短视频合成管线（文案+TTS+数字人+字幕+背景→MP4）", "P0", "2d"),
    task_row("T2.3.5", "视频接入通用预览服务（流式播放+水印）", "P1", "0.5d"),
    task_row("T2.3.6", "Flutter数字人管理页（拍照→上传→训练→管理）", "P0", "1d"),
    task_row("T2.3.7", "Flutter移动端原生拍照（camera包+人脸引导框）", "P1", "0.5d"),
    task_row("T2.3.8", "Flutter短视频合成配置页（文案+声音+数字人+背景模板→一键生成）", "P0", "1.5d"),
    task_row("T2.3.9", "Flutter生成进度页（WebSocket实时进度+视频预览播放）", "P1", "1d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t23, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表3.3　迭代2.3任务清单", styles["Note"]))
story.append(PageBreak())

# ─── 4. 阶段三至五（精简） ─────────────────────────────────
story.append(H("Ch", "四、阶段三：前端业务模块（5-6周）"))
story.append(HR())
story.append(B("目标：构建市场部子系统和招投标合同中心子系统。移动端支持外勤走访/拍照/语音，PC端用于后台管理和合同编辑。"))

t3 = [
    task_row("T3.01", "市场部-客户模型+CRUD API+附件上传", "P0", "1d"),
    task_row("T3.02", "市场部-行为事件记录+满意度+流失预警API", "P1", "1.5d"),
    task_row("T3.03", "市场部-需求预测+营销方案生成API（LLM）", "P0", "1d"),
    task_row("T3.04", "市场部-项目资料汇总+简报生成API（LLM摘要）", "P0", "1d"),
    task_row("T3.05", "市场部-社群分析+NLP情感+活跃度+问答机器人API", "P1", "1.5d"),
    task_row("T3.06", "Flutter市场部全部页面（客户/方案/跟进/社群+仪表盘）", "P0", "4d"),
    task_row("T3.07", "招投标-合同模板+AI合同生成+版本归档API", "P0", "1.5d"),
    task_row("T3.08", "招投标-知识库+ES全文检索+案例推荐API", "P0", "1.5d"),
    task_row("T3.09", "招投标-流程管理+供应商检索+课程匹配API", "P1", "1.5d"),
    task_row("T3.10", "Flutter招投标全部页面（合同/知识库/流程/供应商）", "P0", "3d"),
    task_row("T3.11", "所有文件接入通用预览+四端编译+阶段三收尾", "P0", "1.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t3, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表4.1　阶段三任务总览（13个任务，5-6周）", styles["Note"]))

story.append(H("Ch", "五、阶段四：中台与后端模块（5-6周）"))
story.append(HR())
story.append(B("目标：构建项目管理中台+HR+财务，打通全链路数据流转。移动端支持现场走访和审批，PC端用于中台管控。"))

t4 = [
    task_row("T4.01", "项目管理-项目方案AI生成+行事历API", "P0", "1.5d"),
    task_row("T4.02", "项目管理-走访日志+AI点评+报表生成API", "P0", "1.5d"),
    task_row("T4.03", "项目管理-课件生成+课件管理+总结报告API", "P0", "1.5d"),
    task_row("T4.04", "项目管理-结算检索+标准管理API", "P1", "1d"),
    task_row("T4.05", "Flutter项目管理全部页面（方案/过程/课件/评估/结算）", "P0", "4d"),
    task_row("T4.06", "HR-简历上传+OCR+AI匹配+面试排期API", "P0", "2d"),
    task_row("T4.07", "HR-员工档案+审批流引擎+师资库API", "P0", "1.5d"),
    task_row("T4.08", "Flutter HR全部页面（招募/人事/师资库/审批）", "P0", "3d"),
    task_row("T4.09", "财务-结算同步+费用核算+凭证归档API", "P1", "1.5d"),
    task_row("T4.10", "Flutter财务页面+四端编译+阶段四收尾", "P0", "1.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t4, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表5.1　阶段四任务总览（10个任务，5-6周）", styles["Note"]))
story.append(PageBreak())

story.append(H("Ch", "六、阶段五：联调部署与上线（3-4周）"))
story.append(HR())

story.append(H("Sec", "6.1 迭代5.1 — 系统联调（1周）"))
t51 = [
    task_row("T5.1.1", "前端-中台数据同步接口联调", "P0", "0.5d"),
    task_row("T5.1.2", "中台-财务/人力流转联调", "P0", "0.5d"),
    task_row("T5.1.3", "全模块权限校验一致性测试", "P0", "0.5d"),
    task_row("T5.1.4", "全模块预览流程端到端验证", "P0", "0.5d"),
    task_row("T5.1.5", "四端UI/UX一致性检查", "P1", "0.5d"),
    task_row("T5.1.6", "51需求点逐条验收测试", "P0", "1d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t51, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表6.1　迭代5.1任务清单", styles["Note"]))

story.append(H("Sec", "6.2 迭代5.2 — 性能 + 安全（1-1.5周）"))
t52 = [
    task_row("T5.2.1", "JMeter压测：AI生成≤10s + 知识库50并发 + 预览加载指标", "P0", "1d"),
    task_row("T5.2.2", "音视频克隆时长测试（≤30s）", "P0", "0.5d"),
    task_row("T5.2.3", "TLS传输+AES-256存储加密验证", "P0", "0.5d"),
    task_row("T5.2.4", "审计日志完整性抽查 + 克隆合规校验验证", "P0", "0.5d"),
    task_row("T5.2.5", "四端兼容性测试（Win10/11+iOS15++Android10++Chrome/Edge）", "P0", "1d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t52, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表6.2　迭代5.2任务清单", styles["Note"]))

story.append(H("Sec", "6.3 迭代5.3 — 四端打包分发（0.5-1周）"))
t53 = [
    task_row("T5.3.1", "Windows .exe签名 + Inno Setup安装包制作", "P0", "0.5d"),
    task_row("T5.3.2", "Android .apk签名 + 扫码下载页", "P0", "0.5d"),
    task_row("T5.3.3", "iOS .ipa企业证书签名 + OTA分发plist", "P0", "1d"),
    task_row("T5.3.4", "Web构建 + Nginx部署配置", "P2", "0.5d"),
    task_row("T5.3.5", "四端安装说明文档（含二维码）", "P1", "0.5d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t53, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表6.3　迭代5.3任务清单", styles["Note"]))

story.append(H("Sec", "6.4 迭代5.4 — 私有化部署（1周）"))
t54 = [
    task_row("T5.4.1", "生产环境部署架构图 + docker-compose.prod.yml", "P0", "1d"),
    task_row("T5.4.2", "Nginx反向代理+SSL证书配置", "P0", "0.5d"),
    task_row("T5.4.3", "数据库备份脚本（pg_dump+cron）+ MinIO备份策略", "P0", "0.5d"),
    task_row("T5.4.4", "部署安装手册（含初始化/启动/停止/日志查看）", "P0", "1d"),
    task_row("T5.4.5", "运维手册（备份恢复/监控/故障排查）", "P0", "1d"),
    task_row("T5.4.6", "管理员培训 + 系统交接确认", "P0", "1d"),
]
story.append(make_table(["编号", "任务", "优先级", "估时"], t54, [42, 270, 38, 38], variant=True))
story.append(Paragraph("表6.4　迭代5.4任务清单", styles["Note"]))
story.append(PageBreak())

# ─── 7. 质量保障 ──────────────────────────────────────────
story.append(H("Ch", "七、质量保障策略"))
story.append(HR())

story.append(H("Sec", "7.1 代码质量"))
qa = [
    ["措施", "工具/方法", "频率"],
    ["静态分析", "Flutter: dart analyze / Python: ruff", "每次提交前"],
    ["类型检查", "Dart强类型 + Python mypy（Pydantic天然类型安全）", "持续"],
    ["AI代码审查", "Claude Code review模式", "每天收工前"],
    ["手动回归", "Flutter四端核心流程走查", "每个迭代结束"],
    ["Git规范", "提交信息: [阶段-迭代] 简短描述", "每次提交"],
    ["分支策略", "main（生产）+ phase-X（阶段开发）+ feat/（功能分支）", "持续"],
]
story.append(make_table(["措施", "工具/方法", "频率"], qa, [90, 230, 140], variant=True))
story.append(Paragraph("表7.1　代码质量保障", styles["Note"]))

story.append(H("Sec", "7.2 风险登记册"))
risk = [
    ["R1", "数字人厂商SDK延迟交付", "高", "阶段二前期即启动采购流程，预留2周buffer"],
    ["R2", "OnlyOffice私有部署坑多", "中", "社区版文档完善、Docker部署成熟，预留1周"],
    ["R3", "声音克隆质量不达标", "中", "GPT-SoVITS社区活跃，多试参数组合"],
    ["R4", "Flutter四端兼容bug", "中", "每个迭代都在四端验证，不积累兼容问题"],
    ["R5", "唯一开发者风险", "低", "代码仓库完整+CLAUDE.md文档+AI可接手"],
    ["R6", "API费用超预期", "低", "LLM抽象层可随时切换免费API/本地模型"],
]
story.append(make_table(["ID", "风险", "等级", "缓解措施"], risk, [30, 120, 40, 270], variant=True))
story.append(Paragraph("表7.2　风险登记册", styles["Note"]))
story.append(PageBreak())

# ─── 8. 进度总览 ──────────────────────────────────────────
story.append(H("Ch", "八、进度总览与里程碑"))
story.append(HR())

mile = [
    ["里程碑", "时间节点", "交付物", "验收标准"],
    ["M0 项目启动", "第1周周一", "项目骨架+开发环境", "四端Hello World+API /health"],
    ["M1 阶段一完成", "第5-6周末", "四端预览App V1", "SRS 3.1全部7需求点验收"],
    ["M2 阶段二完成", "第9-11周末", "四端IP工具 V1", "文案→语音→数字人→短视频全流程"],
    ["M3 阶段三完成", "第14-17周末", "四端业务系统 V1", "市场+招投标全功能验收"],
    ["M4 阶段四完成", "第19-23周末", "四端全业务 V1", "三级架构闭环+HR/财务验收"],
    ["M5 项目上线", "第22-27周末", "生产就绪系统", "51需求点全验收+四端安装包就绪"],
]
story.append(make_table(["里程碑", "时间节点", "交付物", "验收标准"], mile, [80, 85, 125, 170], variant=True))
story.append(Paragraph("表8.1　里程碑计划", styles["Note"]))

story.append(H("Sec", "8.1 工时汇总"))
hour_summary = [
    ["阶段", "迭代数", "任务数", "估时(天)", "日历周"],
    ["阶段一", "7", "41", "约35人天", "5-6周"],
    ["阶段二", "3", "25", "约25人天", "4-5周"],
    ["阶段三", "1", "11", "约30人天", "5-6周"],
    ["阶段四", "1", "10", "约28人天", "5-6周"],
    ["阶段五", "4", "22", "约18人天", "3-4周"],
    ["合计", "16", "109", "约136人天", "22-27周"],
]
story.append(make_table(["阶段", "迭代数", "任务数", "估时(天)", "日历周"], hour_summary, [65, 55, 55, 80, 65], variant=True))
story.append(Paragraph("表8.2　工时汇总（含20%buffer）", styles["Note"]))

story.append(H("Sec", "8.2 关键原则"))
story.extend([
    Paragraph("1. <b>每个阶段产出可独立运行的系统</b>，不是半成品拼接", styles["BodyNI"]),
    Paragraph("2. <b>LLM调用统一走抽象层</b>，开发用免费API，生产切本地，仅改环境变量", styles["BodyNI"]),
    Paragraph("3. <b>四端同步验证</b>，不在一个平台积累技术债", styles["BodyNI"]),
    Paragraph("4. <b>权限/审计/水印从第一天就有</b>，不是后期补丁", styles["BodyNI"]),
    Paragraph("5. <b>移动端原生能力优先</b>（相机/录音/推送），不降级为网页", styles["BodyNI"]),
    Paragraph("6. <b>每个迭代结束标记git tag</b>，方便回溯和演示", styles["BodyNI"]),
])

# ─── 末页 ────────────────────────────────────────────────
story.append(S(40))
story.append(HRFlowable(width="50%", thickness=1, color=BORDER, spaceBefore=10, spaceAfter=10))
story.append(H("Note", f"— 文档结束 | 生成日期：{datetime.now().strftime('%Y年%m月%d日')} —"))
story.append(H("Note", "Flutter全端架构 · 一人+AI开发模式 · 5阶段109任务"))

doc.build(story)
print(f"Dev plan PDF: {os.path.abspath(output_path)}")
