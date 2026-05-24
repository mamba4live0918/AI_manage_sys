#!/usr/bin/env python3
"""生成《公司AI场景建设系统 — 项目可行性分析与分阶段SRS报告》PDF — Flutter全端版"""

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
pdfmetrics.registerFont(TTFont("SimFang", os.path.join(FONT_DIR, "simfang.ttf")))

# ─── 颜色 ─────────────────────────────────────────────────
PRIMARY = HexColor("#1a56db")
DARK_BG = HexColor("#1e293b")
TABLE_HEADER = HexColor("#2563eb")
TABLE_ROW_ALT = HexColor("#f8fafc")
BORDER = HexColor("#cbd5e1")
SAVE_GREEN = HexColor("#059669")
ACCENT_GREEN = HexColor("#16a34a")
ACCENT_ORANGE = HexColor("#ea580c")

# ─── 样式 ─────────────────────────────────────────────────
styles = getSampleStyleSheet()
styles.add(ParagraphStyle("CoverTitle", fontName="SimHei", fontSize=28, leading=40, alignment=TA_CENTER, textColor=black))
styles.add(ParagraphStyle("CoverSubtitle", fontName="SimSun", fontSize=14, leading=22, alignment=TA_CENTER, textColor=grey))
styles.add(ParagraphStyle("ChapterTitle", fontName="SimHei", fontSize=20, leading=28, textColor=PRIMARY, spaceBefore=20, spaceAfter=14))
styles.add(ParagraphStyle("SectionTitle", fontName="SimHei", fontSize=15, leading=22, textColor=DARK_BG, spaceBefore=16, spaceAfter=8))
styles.add(ParagraphStyle("SubSectionTitle", fontName="SimHei", fontSize=12, leading=18, textColor=HexColor("#334155"), spaceBefore=10, spaceAfter=6))
styles.add(ParagraphStyle("CNBody", fontName="SimSun", fontSize=10.5, leading=18, alignment=TA_JUSTIFY, spaceBefore=2, spaceAfter=6, firstLineIndent=21))
styles.add(ParagraphStyle("CNBodyNI", fontName="SimSun", fontSize=10.5, leading=18, alignment=TA_JUSTIFY, spaceBefore=2, spaceAfter=6))
styles.add(ParagraphStyle("CellStyle", fontName="SimSun", fontSize=9, leading=14, alignment=TA_CENTER))
styles.add(ParagraphStyle("CellStyleV", fontName="SimSun", fontSize=9, leading=14, alignment=TA_JUSTIFY))
styles.add(ParagraphStyle("SmallNote", fontName="SimSun", fontSize=8, leading=12, textColor=grey, alignment=TA_CENTER))
styles.add(ParagraphStyle("CaptionStyle", fontName="SimKai", fontSize=9, leading=14, textColor=grey, alignment=TA_CENTER, spaceBefore=4, spaceAfter=10))
styles.add(ParagraphStyle("TOCItem", fontName="SimSun", fontSize=11, leading=24, leftIndent=20))

# ─── 工具函数 ─────────────────────────────────────────────
def H(level, text):
    """标题快捷函数"""
    style_map = {"chapter": "ChapterTitle", "s": "SectionTitle", "ss": "SubSectionTitle"}
    return Paragraph(text, styles[style_map.get(level, "SectionTitle")])

def B(text):
    return Paragraph(text, styles["CNBody"])

def BN(text):
    return Paragraph(text, styles["CNBodyNI"])

def S(h=6):
    return Spacer(1, h)

def HR():
    return HRFlowable(width="100%", thickness=0.5, color=BORDER, spaceBefore=6, spaceAfter=6)

def make_table(headers, rows, col_widths, variant=False):
    """variant=True 使用左对齐单元格"""
    cell_style = "CellStyleV" if variant else "CellStyle"
    header_paras = [Paragraph(f"<b>{h}</b>", styles["CellStyle"]) for h in headers]
    data = [header_paras]
    for row in rows:
        data.append([Paragraph(str(c), styles[cell_style]) if not isinstance(c, Paragraph) else c for c in row])

    if col_widths is None:
        col_widths = [460 / len(headers)] * len(headers)

    t = Table(data, colWidths=col_widths, repeatRows=1)
    cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "SimHei"),
        ("FONTSIZE", (0, 0), (-1, 0), 10),
        ("BOTTOMPADDING", (0, 0), (-1, 0), 10),
        ("TOPPADDING", (0, 0), (-1, 0), 10),
        ("FONTNAME", (0, 1), (-1, -1), "SimSun"),
        ("FONTSIZE", (0, 1), (-1, -1), 9),
        ("TOPPADDING", (0, 1), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 1), (-1, -1), 6),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]
    for i in range(1, len(data)):
        if i % 2 == 0:
            cmds.append(("BACKGROUND", (0, i), (-1, i), TABLE_ROW_ALT))
    t.setStyle(TableStyle(cmds))
    return t

def bullet(items, symbol="●"):
    return [Paragraph(f"{symbol} {item}", styles["CNBodyNI"]) for item in items]

def green(text):
    return Paragraph(f'<font color="#059669"><b>{text}</b></font>', styles["CellStyle"])

def deliver_list(items):
    return [BN(f"● {item}") for item in items]

# ═══════════════════════════════════════════════════════════
output_path = "AI场景建设系统_可行性分析与分阶段SRS报告.pdf"
doc = SimpleDocTemplate(
    output_path, pagesize=A4,
    leftMargin=22*mm, rightMargin=22*mm,
    topMargin=20*mm, bottomMargin=20*mm,
    title="公司AI场景建设系统 — 项目可行性分析与分阶段SRS报告",
    author="项目评估组",
)
story = []

# ═══════════════════════════════════════════════════════════
# 封面
# ═══════════════════════════════════════════════════════════
story.append(S(60))
story.append(Paragraph("公司AI场景建设系统", styles["CoverTitle"]))
story.append(S(8))
story.append(Paragraph("项目可行性分析与分阶段SRS报告", styles["CoverTitle"]))
story.append(S(20))
story.append(HRFlowable(width="60%", thickness=2, color=PRIMARY, spaceBefore=10, spaceAfter=10))
story.append(S(12))
story.append(Paragraph("Flutter全端架构 · 一套代码四端交付", styles["CoverSubtitle"]))
story.append(Paragraph("Windows .exe | iOS .ipa | Android .apk | Web", styles["CoverSubtitle"]))
story.append(Paragraph("前端业务 · 中台管控 · 后端职能 · 讲师IP子系统", styles["CoverSubtitle"]))
story.append(S(30))
story.append(Paragraph(f"报告日期：{datetime.now().strftime('%Y年%m月%d日')}", styles["CoverSubtitle"]))
story.append(Paragraph("版本：V2.0（Flutter全端）", styles["CoverSubtitle"]))
story.append(Paragraph("密级：内部", styles["CoverSubtitle"]))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 目录
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "目　录"))
story.append(HR())
toc = [
    ("第一章", "项目概述与需求统计"),
    ("第二章", "全端架构选型（Flutter 一套代码四端交付）"),
    ("第三章", "开发模式对比分析（独立开发+AI vs 市场团队）"),
    ("第四章", "成本与投入产出分析"),
    ("第五章", "分阶段迭代总体规划"),
    ("第六章", "阶段一 SRS：通用基础设施与权限文件预览"),
    ("第七章", "阶段二 SRS：讲师IP专属子系统"),
    ("第八章", "阶段三 SRS：前端业务模块（市场部 + 招投标）"),
    ("第九章", "阶段四 SRS：中台与后端模块（项目管理 + HR + 财务）"),
    ("第十章", "阶段五：联调部署与上线"),
    ("附录", "全系统需求追溯矩阵"),
]
for ch, title in toc:
    story.append(Paragraph(
        f'<font face="SimHei" size="12"><b>{ch}</b></font>　'
        f'<font face="SimSun" size="11">{title}</font>',
        styles["TOCItem"]
    ))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第一章：项目概述
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第一章　项目概述与需求统计"))
story.append(HR())

story.append(H("s", "1.1 项目背景"))
story.append(B("随着公司业务规模扩张，市场部、招投标中心、项目管理部、人力资源及财务中心在日常运营中面临大量重复性人工劳动。同时，讲师个人品牌（IP）运营需要内容生产工具支撑。为提升业务效率、降低人力成本、增强数据资产安全管控，提出建设全链路AI赋能系统。"))

story.append(H("s", "1.2 系统架构分层"))
story.append(BN("<b>业务架构：三级架构 + 专属子系统 + 通用能力层</b>"))
story.append(S(4))
arch_rows = [
    ["前端层", "面向一线业务部门", "市场部子系统、招投标合同中心子系统"],
    ["中台层", "项目管理中枢", "项目管理部子系统（方案/过程/课件/评估/结算）"],
    ["后端层", "职能支撑", "人力资源中心、财务中心"],
    ["专属子系统", "讲师个人IP工具", "AI文案、短视频、声音克隆、数字人克隆"],
    ["通用能力层", "全系统复用", "权限化页内文件预览、统一鉴权网关、审计日志"],
]
story.append(make_table(["层级", "定位", "覆盖模块"], arch_rows, [80, 120, 260], variant=True))
story.append(Paragraph("表1.1　业务架构分层", styles["CaptionStyle"]))

story.append(H("s", "1.3 技术架构：Flutter全端"))
story.append(B("本系统采用 Flutter 作为统一前端框架，一套 Dart 代码编译输出四个平台产物，后端采用 Python FastAPI 提供 REST API："))
story.append(S(4))
flutter_rows = [
    ["Windows PC", ".exe", "公司办公电脑安装，桌面快捷方式启动", "文件管理/预览/管理后台"],
    ["iOS", ".ipa", "企业证书分发 / TestFlight 内测", "讲师外勤/移动审批/录音拍照"],
    ["Android", ".apk", "扫码下载安装", "同上，覆盖安卓用户"],
    ["Web", "HTML/JS", "浏览器访问（备选入口）", "临时访问/未安装App时使用"],
    ["后端", "FastAPI", "REST API 统一服务所有端", "业务逻辑/AI推理/文件存储"],
]
story.append(make_table(["平台", "产物", "分发方式", "典型场景"], flutter_rows, [70, 70, 150, 170], variant=True))
story.append(Paragraph("表1.2　Flutter全端交付矩阵", styles["CaptionStyle"]))

story.append(H("s", "1.4 用户角色"))
story.append(B("八类用户：市场专员、招投标专员、项目管理员、讲师、HR、财务人员、系统管理员、权限配置管理员。不同角色对应不同功能权限和数据访问范围。"))

story.append(H("s", "1.5 需求全景统计"))
req_rows = [
    ["通用文件预览", "权限校验、多格式预览、水印溯源、分级下载、权限配置、状态标注、流式加载", "7"],
    ["市场部子系统", "客户管理、营销方案生成、项目跟进、社群运营、预览配套", "5"],
    ["招投标子系统", "合同文本AI生成、知识库管理、流程管理、供应商师资库", "4"],
    ["项目管理中台", "项目方案、过程管理、培训课件、评估总结、结算管控", "5"],
    ["人力资源", "招募系统、人事管理AI、师资管理库", "3"],
    ["财务中心", "结算数据流转、费用核算、凭证归档", "3"],
    ["讲师IP子系统", "营销文案、短视频生产、声音克隆、数字人克隆、素材预览", "5"],
    ["非功能需求", "性能6项 + 安全4项 + 易用性3项 + 兼容性1项", "14"],
    ["接口需求", "内部接口3项 + 外部接口3项 + 预览专用接口1项", "7"],
    ["合计", "", "51"],
]
story.append(make_table(["模块", "主要内容", "需求点数"], req_rows, [100, 280, 80]))
story.append(Paragraph("表1.3　全系统需求统计总览", styles["CaptionStyle"]))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第二章：全端架构选型
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第二章　全端架构选型"))
story.append(HR())

story.append(H("s", "2.1 需求约束"))
story.extend(bullet([
    "必须具备可安装的移动端App（非浏览器网页）",
    "PC端必须具备可安装的桌面程序（非浏览器网页）",
    "一人+AI开发，必须一套代码覆盖所有端",
    "支持原生能力：拍照、录音、推送通知、离线存储",
]))

story.append(H("s", "2.2 跨平台方案对比"))
cross_rows = [
    ["方案", "一套代码", "iOS App", "Android App", "Windows .exe", "Web", "原生能力", "AI友好度"],
    ["Flutter", Paragraph('<font color="#059669"><b>✅</b></font>', styles["CellStyle"]), "✅", "✅", "✅", "✅", "强", "高"],
    ["React Native + React", "❌ 两套", "✅", "✅", "❌ Electron", "✅", "中", "中高"],
    ["Kotlin Multiplatform", "❌ 部分共享", "✅", "✅", "❌", "❌", "强", "低"],
    ["纯Web(PWA)", "✅", "❌ 网页", "❌ 网页", "❌ 网页", "✅", "弱", "高"],
]
story.append(make_table(cross_rows[0], cross_rows[1:], [55, 50, 55, 65, 55, 45, 55, 80], variant=True))
story.append(Paragraph("表2.1　跨平台方案对比", styles["CaptionStyle"]))

story.append(H("s", "2.3 结论：Flutter"))
story.append(B("Flutter 是唯一满足「一套代码 + 原生App安装 + Windows桌面程序」三重要求的方案。Dart语言与TypeScript高度相似，学习曲线低，AI编程助手训练数据充足，适合一人+AI的开发模式。"))
story.append(S(4))
benefit_rows = [
    ["维度", "Flutter优势"],
    ["代码复用率", "95%+（UI层+业务逻辑层完全共享，仅平台配置差异）"],
    ["Windows .exe", "原生编译，非Electron套壳，体积小、性能高"],
    ["移动端安装", ".ipa/.apk原生安装包，App级体验（推送/离线/原生相机）"],
    ["AI辅助效率", "Flutter/Dart社区大，AI代码生成质量与React同级"],
    ["UI一致性", "Material Design 3，四端视觉统一"],
    ["状态管理", "Riverpod（推荐），AI理解度高，代码可维护性强"],
]
story.append(make_table(["维度", "Flutter优势"], benefit_rows, [100, 360], variant=True))
story.append(Paragraph("表2.2　Flutter全端方案优势", styles["CaptionStyle"]))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第三章：开发模式对比
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第三章　开发模式对比分析"))
story.append(HR())

story.append(H("s", "3.1 两种开发模式"))
story.append(B("模式A——独立开发（1人+AI辅助），由一名全栈工程师借助AI编程助手完成全部开发。模式B——市场团队开发，按市场标准配置组建技术团队。"))

story.append(H("s", "3.2 团队配置对比"))
team_rows = [
    ["角色", "模式A：独立开发+AI", "模式B：市场团队"],
    ["项目经理", "客户兼任（对接人）", "1人（全职）"],
    ["架构师", "AI辅助设计 + 人工决策", "1人（兼职/外部顾问）"],
    ["Flutter全栈", "1人（全栈+AI）", "2人（iOS+Android）"],
    ["后端工程师", "（同一人，AI辅助）", "2人"],
    ["AI/算法工程师", "（同一人，AI辅助）", "1人"],
    ["测试工程师", "AI生成测试 + 人工验证", "1人"],
    ["运维/DevOps", "AI辅助Docker配置", "1人（兼）"],
    ["总人数", "1人 + AI", "7-9人"],
]
story.append(make_table(["角色", "模式A：独立开发+AI", "模式B：市场团队"], team_rows, [100, 180, 180]))
story.append(Paragraph("表3.1　团队配置对比", styles["CaptionStyle"]))

story.append(H("s", "3.3 AI辅助效率分析"))
eff_rows = [
    ["任务类型", "传统人天", "AI辅助人天", "提效倍数", "说明"],
    ["标准CRUD API开发", "20", "4", "5.0x", "AI生成质量最高"],
    ["Flutter UI（Material Design）", "20", "5", "4.0x", "组件化模式AI掌握好"],
    ["数据库设计与迁移", "6", "2", "3.0x", "模式固定"],
    ["用户认证与RBAC", "10", "3", "3.3x", "成熟模式"],
    ["文件存储集成（MinIO）", "8", "2.5", "3.2x", "SDK标准调用"],
    ["OnlyOffice文档预览集成", "15", "6", "2.5x", "配置步骤多"],
    ["动态水印（Flutter Canvas）", "5", "2", "2.5x", "Canvas方案成熟"],
    ["LLM推理部署 + API", "8", "3", "2.7x", "部署脚本标准化"],
    ["提示词模板引擎", "10", "3", "3.3x", "模板逻辑清晰"],
    ["声音克隆部署联调", "15", "10", "1.5x", "调优靠人工试错"],
    ["数字人SDK对接", "20", "12", "1.7x", "厂商文档参差"],
    ["视频合成管线（ffmpeg）", "18", "12", "1.5x", "时间轴试错"],
    ["Flutter平台适配（4端）", "12", "6", "2.0x", "AI帮写平台配置"],
    ["系统部署联调", "15", "10", "1.5x", "私有化环境差异"],
    ["App打包分发", "8", "4", "2.0x", "流程标准化"],
]
story.append(make_table(["任务类型", "传统人天", "AI辅助人天", "提效倍数", "说明"], eff_rows, [130, 65, 65, 60, 140]))
story.append(Paragraph("表3.2　AI辅助效率对比（15类关键任务）", styles["CaptionStyle"]))

story.append(H("s", "3.4 总体工期对比"))
time_rows = [
    ["开发指标", "模式A：独立开发+AI", "模式B：市场团队"],
    ["总人天（含buffer）", "180-210人天", "270-310人天"],
    ["日历工期", "6-7个月", "4-5个月（并行）"],
    ["人均效率（人天/功能点）", "3.5-4.1", "5.3-6.1"],
    ["项目管理开销", "极低（自管理）", "约15%工时（会议/沟通）"],
    ["需求变更响应", "即时（单人决策）", "需多轮讨论"],
]
story.append(make_table(["开发指标", "模式A：独立开发+AI", "模式B：市场团队"], time_rows, [120, 170, 170]))
story.append(Paragraph("表3.3　总体工期与效率对比", styles["CaptionStyle"]))

story.append(H("s", "3.5 综合结论"))
story.extend(bullet([
    "总人力成本降低 65%-70%（1人 vs 7-9人）",
    "Flutter一套代码覆盖四个平台，无需多团队协同",
    "代码一致性、可维护性显著优于多人团队",
    "需求响应速度极快，无沟通损耗",
    "日历工期比市场团队多约2个月，但总成本仅为市场方案的35%",
], "✓"))
story.extend(bullet([
    "日历工期略长（单人串行 vs 多人并行）",
    "声音克隆、数字人对接等需试错的环节AI帮助有限",
    "缺乏第二人审查，关键逻辑需格外谨慎",
    "人员风险：唯一开发者若离开，需交接成本",
], "△"))
story.append(B("<b>推荐结论：</b>本项目的规模、复杂度和预算约束下，<b>独立开发+AI+Flutter全端模式具备最优投入产出比</b>。"))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第四章：成本分析
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第四章　成本与投入产出分析"))
story.append(HR())

story.append(H("s", "4.1 人力成本对比"))
cost_rows = [
    ["费用项", "模式A：独立开发+AI", "模式B：市场团队", "节省"],
    ["项目周期", "6.5个月（约）", "4.5个月（约）", "—"],
    ["人力投入", "1人 × 6.5月 = 6.5人月", "8人 × 4.5月 = 36人月", "29.5人月"],
    ["月均薪资（二线城市）", "¥25,000（全栈）", "¥140,000（8人）", "—"],
    ["人力总成本", green("约 ¥162,500"), "约 ¥630,000", green("约 ¥467,500")],
]
story.append(make_table(["费用项", "模式A：独立开发+AI", "模式B：市场团队", "节省"], cost_rows, [105, 125, 125, 105]))
story.append(Paragraph("表4.1　人力成本对比", styles["CaptionStyle"]))

story.append(H("s", "4.2 硬件成本（私有部署）"))
hw_rows = [
    ["设备", "用途", "配置", "参考价格"],
    ["GPU服务器", "LLM推理+声音克隆+数字人", "1×A100 80G / 2×RTX 4090", "¥15-25万"],
    ["通用服务器", "应用+数据库+缓存", "64G内存+4TB SSD", "¥5-8万"],
    ["NAS/磁盘阵列", "文件存储（音视频）", "8TB+RAID5", "¥3-5万"],
    ["网络设备", "交换机+UPS", "千兆+3kVA UPS", "¥1-2万"],
    ["硬件合计", "", "", "<b>约 ¥24-40万</b>"],
]
story.append(make_table(["设备", "用途", "配置", "参考价格"], hw_rows, [85, 115, 155, 105]))
story.append(Paragraph("表4.2　硬件投入估算（一次性）", styles["CaptionStyle"]))

story.append(H("s", "4.3 第三方服务（年度）"))
third_rows = [
    ["服务项", "用途", "提供商参考", "年费估算"],
    ["数字人克隆私有化授权", "SRS 3.5 数字人", "科大讯飞/硅基智能/商汤", "¥10-20万"],
    ["OnlyOffice 社区版", "文档预览", "OnlyOffice", "¥0"],
    ["Flutter", "全端框架", "Google（开源）", "¥0"],
    ["苹果开发者账号", "iOS签名分发", "Apple", "¥688/年"],
    ["第三方合计/年", "", "", "<b>约 ¥10-20万/年</b>"],
]
story.append(make_table(["服务项", "用途", "提供商参考", "年费估算"], third_rows, [110, 110, 120, 120]))
story.append(Paragraph("表4.3　第三方服务成本（年度）", styles["CaptionStyle"]))

story.append(H("s", "4.4 总成本概览（首年）"))
total_rows = [
    ["成本类别", "模式A：独立+AI+Flutter", "模式B：市场团队", "节省"],
    ["人力成本", "¥16.25万", "¥63万", "¥46.75万"],
    ["硬件（一次性）", "¥32万（取中值）", "¥32万", "¥0"],
    ["第三方授权（年）", "¥15万（取中值）", "¥15万", "¥0"],
    ["办公/管理/其他", "¥3万", "¥10万", "¥7万"],
    ["苹果开发者账号", "¥0.07万", "¥0.07万", "¥0"],
    ["首年总计", green("约 ¥66.32万"), "约 ¥120.07万", green("约 ¥53.75万")],
]
story.append(make_table(["成本类别", "模式A：独立+AI+Flutter", "模式B：市场团队", "节省"], total_rows, [105, 125, 125, 105]))
story.append(Paragraph("表4.4　首年总成本对比", styles["CaptionStyle"]))
story.append(B("<b>结论：</b>独立+AI+Flutter模式首年总成本约为市场团队的<b>55%</b>，节省约<b>53.75万元</b>。后续年份仅需第三方授权续费（约15万/年）+ 苹果开发者续费 + 少量维护。"))

story.append(H("s", "4.5 市场报价参考"))
market_rows = [
    ["服务类型", "范围", "市场报价"],
    ["单体模块开发", "仅文件预览+基本权限（Web）", "¥15-25万"],
    ["含AI能力系统", "文件预览+1-2个AI模块（Web）", "¥35-50万"],
    ["全系统全端", "5业务域+讲师IP+AI全能力+四端App", "¥120-200万"],
    ["含一年运维", "全系统+维护+迭代+App更新", "¥180-300万"],
]
story.append(make_table(["服务类型", "范围", "市场报价"], market_rows, [120, 210, 130]))
story.append(Paragraph("表4.5　外部承接市场报价参考", styles["CaptionStyle"]))
story.append(B("本项目自建首年投入约66万，较外部承接全系统全端开发（120-200万）节省<b>54-134万</b>，且系统所有权完全归属公司。"))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第五章：分阶段总体规划
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第五章　分阶段迭代总体规划"))
story.append(HR())

story.append(B("本系统共划分为五个阶段，每个阶段均产出可独立交付、独立验收的子系统。总体遵循「基础设施先行 → 高ROI模块优先 → 业务全覆盖 → 全端打包上线」的交付策略。Flutter全端从阶段一即开始，每个阶段交付物均包含 Windows .exe + iOS .ipa + Android .apk + Web 四端。"))

story.append(H("s", "5.1 总览路线图"))
road_rows = [
    ["阶段", "内容", "周期", "累计需求点", "交付物"],
    ["阶段一", "通用基础设施+权限文件预览（Flutter四端）", "5-6周", "7", "四端预览App"],
    ["阶段二", "讲师IP子系统（文案/声音/数字人/短视频）", "4-5周", "12", "四端IP工具"],
    ["阶段三", "前端业务模块（市场部+招投标）", "5-6周", "21", "四端业务系统"],
    ["阶段四", "中台+后端模块（项目管理+HR+财务）", "5-6周", "35", "四端全业务"],
    ["阶段五", "联调+安全+打包分发+部署上线", "3-4周", "51", "生产就绪"],
    ["合计", "", "22-27周（约6-7个月）", "", ""],
]
story.append(make_table(["阶段", "内容", "周期", "累计需求点", "交付物"], road_rows, [55, 180, 65, 60, 100]))
story.append(Paragraph("表5.1　分阶段总体规划（Flutter全端版）", styles["CaptionStyle"]))

story.append(H("s", "5.2 阶段依赖关系"))
story.append(BN("阶段一（基础设施）为后续所有阶段的<b>前置依赖</b>。"))
story.append(BN("阶段二（讲师IP）与阶段三、四<b>无依赖</b>，是最快产生商业价值差异化的模块。"))
story.append(BN("阶段三（前端业务）和阶段四（中台+后端）有<b>数据流依赖</b>，建议阶段三完成后立即启动阶段四。"))
story.append(BN("阶段五（打包上线）依赖前四阶段全部完成，并包含四端打包签名分发。"))

story.append(H("s", "5.3 需求追溯矩阵（简）"))
mapping_rows = [
    ["阶段", "覆盖SRS章节", "需求编号"],
    ["阶段一", "3.1 通用权限预览", "1.1 ~ 1.7"],
    ["阶段二", "3.5 讲师IP子系统", "7.1 ~ 7.5"],
    ["阶段三", "3.2.1 市场部 + 3.2.2 招投标", "2.1 ~ 2.5, 3.1 ~ 3.4"],
    ["阶段四", "3.3 中台 + 3.4.1 HR + 3.4.2 财务", "4.1 ~ 4.5, 5.1 ~ 5.3, 6.1 ~ 6.3"],
    ["阶段五", "4 非功能 + 5 接口", "8.1 ~ 8.14, 9.1 ~ 9.7"],
]
story.append(make_table(["阶段", "覆盖SRS章节", "需求编号"], mapping_rows, [70, 190, 200], variant=True))
story.append(Paragraph("表5.2　需求追溯矩阵", styles["CaptionStyle"]))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第六章：阶段一 SRS
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第六章　阶段一 SRS：通用基础设施与权限文件预览"))
story.append(HR())

story.append(H("s", "6.1 阶段目标"))
story.append(B("搭建Flutter全端项目骨架 + FastAPI后端，实现全系统权限化页内文件预览能力。本阶段完成后，用户可通过 Windows .exe 桌面程序、iOS/Android App 完成文件上传、目录管理、多格式页内预览、权限管控和水印保护，管理员可配置分级权限并查阅审计日志。"))

story.append(H("s", "6.2 功能需求清单"))
f1_rows = [
    ["F1.1", "用户认证", "注册、JWT登录、Token持久化、四端统一认证"],
    ["F1.2", "RBAC角色模型", "4级角色（admin/dept_manager/project_manager/general）"],
    ["F1.3", "文件上传", "支持Word/Excel/PDF/图片/音频/视频上传，自动MIME识别"],
    ["F1.4", "目录管理", "文件夹创建/删除、面包屑导航、多级目录"],
    ["F1.5", "文档预览", "集成OnlyOffice Docs，Word/Excel/PDF页内预览"],
    ["F1.6", "媒体预览", "图片/音频/视频原生播放器，流式分片加载"],
    ["F1.7", "动态水印", "Flutter Canvas水印叠加（用户名+部门+日期）"],
    ["F1.8", "右键/手势防护", "桌面端禁止右键，移动端禁止截屏检测"],
    ["F1.9", "分级下载", "仅授权用户可下载源文件"],
    ["F1.10", "权限校验网关", "5级ACL（用户→角色→部门→项目→父目录继承）"],
    ["F1.11", "权限配置界面", "管理员可视化管理ACL，授予预览/下载/编辑权限"],
    ["F1.12", "权限状态标注", "文件列表直观显示可预览/可下载/无权限Tag"],
    ["F1.13", "审计日志", "预览/下载/上传/删除/权限变更全程留痕"],
]
story.append(make_table(["编号", "功能", "详细描述"], f1_rows, [45, 80, 335], variant=True))
story.append(Paragraph("表6.1　阶段一功能需求清单", styles["CaptionStyle"]))

story.append(H("s", "6.3 非功能需求"))
nf1_rows = [
    ["类型", "指标", "要求"],
    ["性能", "文档预览加载", "≤ 2秒"],
    ["性能", "图片预览加载", "≤ 1.5秒"],
    ["性能", "视频首帧加载", "≤ 3秒"],
    ["安全", "数据加密", "传输TLS + 存储AES-256"],
    ["安全", "鉴权", "JWT + 每个预览/下载请求独立鉴权"],
    ["安全", "水印溯源", "水印绑定用户身份+时间戳"],
    ["兼容", "平台", "Windows 10/11 + iOS 15+ + Android 10+"],
    ["兼容", "文件格式", "Word/Excel/PDF/MP4/JPG/PNG/MP3/WAV"],
    ["兼容", "预览格式", "文档+图片+音频+视频页内渲染"],
]
story.append(make_table(["类型", "指标", "要求"], nf1_rows, [80, 130, 250]))
story.append(Paragraph("表6.2　阶段一非功能需求", styles["CaptionStyle"]))

story.append(H("s", "6.4 接口需求"))
if1_rows = [
    ["接口", "方法", "路径", "说明"],
    ["用户注册", "POST", "/api/auth/register", "注册新用户"],
    ["用户登录", "POST", "/api/auth/login", "OAuth2密码模式，返回JWT"],
    ["获取当前用户", "GET", "/api/auth/me", "返回当前用户信息"],
    ["文件列表", "GET", "/api/files/list?parent_id=", "按目录列出文件"],
    ["文件上传", "POST", "/api/files/upload", "multipart/form-data"],
    ["创建文件夹", "POST", "/api/files/folder", "创建目录"],
    ["删除文件", "DELETE", "/api/files/{id}", "删除文件或空目录"],
    ["预览文件", "GET", "/api/preview/file/{id}", "返回预览URL+配置"],
    ["下载文件", "GET", "/api/preview/download/{id}", "流式下载，独立鉴权"],
    ["OnlyOffice配置", "GET", "/api/preview/onlyoffice/config/{id}", "编辑器配置JSON"],
    ["查询权限", "GET", "/api/permissions/resource/{id}", "查某资源的ACL"],
    ["授予权限", "POST", "/api/permissions/grant", "添加ACL条目"],
    ["撤销权限", "DELETE", "/api/permissions/revoke/{id}", "移除ACL条目"],
    ["审计日志", "GET", "/api/audit/logs?page=&action=", "分页查询"],
]
story.append(make_table(["接口", "方法", "路径", "说明"], if1_rows, [65, 50, 185, 160], variant=True))
story.append(Paragraph("表6.3　阶段一接口清单", styles["CaptionStyle"]))

story.append(H("s", "6.5 技术栈"))
tech1_rows = [
    ["层次", "选型", "版本/说明"],
    ["前端框架", "Flutter 3.x + Dart", "一套代码，Material Design 3"],
    ["状态管理", "Riverpod 2.x", "编译时安全，AI友好"],
    ["HTTP客户端", "Dio", "拦截器 + JWT自动注入"],
    ["后端框架", "Python FastAPI 0.115+", "async/await异步"],
    ["ORM", "SQLAlchemy 2.0", "async session + PostgreSQL"],
    ["数据库", "PostgreSQL 16", "UUID、JSONB、全文检索"],
    ["缓存", "Redis 7", "Token黑名单 + 热点缓存"],
    ["文件存储", "MinIO", "S3兼容，私有化部署"],
    ["文档预览", "OnlyOffice Docs（社区版）", "私有化部署"],
    ["部署", "Docker Compose", "一键启动全部基础设施"],
    ["四端产物", ".exe / .ipa / .apk / Web", "flutter build 命令"],
]
story.append(make_table(["层次", "选型", "版本/说明"], tech1_rows, [100, 160, 200]))
story.append(Paragraph("表6.4　阶段一技术栈", styles["CaptionStyle"]))

story.append(H("s", "6.6 交付物清单"))
story.extend(deliver_list([
    "Flutter项目源码（一套代码，四端共用）",
    "FastAPI后端项目源码（14个接口）",
    "Docker Compose一键部署配置（PostgreSQL+Redis+MinIO+OnlyOffice）",
    "数据库初始化脚本（表结构+索引+默认管理员）",
    "Windows .exe 安装包",
    "iOS .ipa（企业证书签名）",
    "Android .apk",
    "Web部署包（备选入口）",
    "运维部署手册",
]))
story.append(S(10))
story.append(B("<b>预估工期：5-6周 | 交付标准：四端可独立运行，覆盖SRS 3.1全部7个需求点。</b>"))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第七章：阶段二 SRS（讲师IP）
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第七章　阶段二 SRS：讲师IP专属子系统"))
story.append(HR())

story.append(H("s", "7.1 阶段目标"))
story.append(B("在阶段一基础设施之上，构建讲师IP专属数字化工具。面向金融理财师场景，实现从营销文案生成到短视频生产全流程AI化。移动端（iOS/Android）可调用原生相机拍照和麦克风录音用于素材采集，PC端（Windows .exe）用于后台内容管理和批量生产。"))

story.append(H("s", "7.2 功能需求清单"))
f2_rows = [
    ["F2.1", "LLM推理部署", "私有化部署Qwen2.5 14B，提供OpenAI兼容API"],
    ["F2.2", "营销文案生成", "公众号/朋友圈模板+参数输入→AI生成→二次编辑"],
    ["F2.3", "声音样本管理", "移动端原生录音→上传样本→管理"],
    ["F2.4", "声音克隆训练", "GPT-SoVITS微调管线，单次≤30分钟"],
    ["F2.5", "语音合成", "文本→克隆语音（≤15秒/30字）"],
    ["F2.6", "数字人形象管理", "移动端拍照→上传→生成数字人形象"],
    ["F2.7", "数字人口播", "文本+形象+声音→口播视频（厂商私有化SDK）"],
    ["F2.8", "短视频合成", "文案→TTS→数字人→字幕→MP4（ffmpeg管线）"],
    ["F2.9", "短视频生成界面", "统一配置页：模板+声音+数字人→一键生成"],
    ["F2.10", "讲师素材库", "按讲师隔离的素材管理，支持CRUD"],
    ["F2.11", "素材权限预览", "复用阶段一预览服务，讲师+管理员可预览"],
    ["F2.12", "合规授权校验", "克隆前强制授权确认+记录留痕"],
]
story.append(make_table(["编号", "功能", "详细描述"], f2_rows, [45, 85, 330], variant=True))
story.append(Paragraph("表7.1　阶段二功能需求清单", styles["CaptionStyle"]))

story.append(H("s", "7.3 非功能需求"))
nf2_rows = [
    ["类型", "指标", "要求"],
    ["性能", "AI文案生成响应", "≤ 10秒"],
    ["性能", "单条音视频克隆生成", "≤ 30秒"],
    ["性能", "语音合成", "≤ 15秒（30字以内）"],
    ["安全", "克隆合规", "每次克隆前强制授权确认"],
    ["安全", "素材隔离", "讲师间素材完全隔离"],
    ["可用性", "二次编辑", "生成内容支持人工修改保存"],
    ["可用性", "模板自定义", "管理员可新增/修改文案模板"],
    ["平台", "移动端原生", "iOS/Android调用原生相机+麦克风"],
]
story.append(make_table(["类型", "指标", "要求"], nf2_rows, [80, 130, 250]))
story.append(Paragraph("表7.2　阶段二非功能需求", styles["CaptionStyle"]))

story.append(H("s", "7.4 接口需求（增量）"))
if2_rows = [
    ["接口", "方法", "路径", "说明"],
    ["模板列表", "GET", "/api/ip/templates", "获取文案模板"],
    ["生成文案", "POST", "/api/ip/generate/text", "AI生成文案"],
    ["上传声音样本", "POST", "/api/ip/voice/upload", "上传训练音频"],
    ["训练声音模型", "POST", "/api/ip/voice/train", "触发克隆训练"],
    ["语音合成", "POST", "/api/ip/voice/synthesize", "文字→克隆语音"],
    ["上传数字人照片", "POST", "/api/ip/avatar/upload", "照片→数字人"],
    ["数字人口播", "POST", "/api/ip/avatar/video", "生成口播视频"],
    ["合成短视频", "POST", "/api/ip/video/compose", "组装成品"],
    ["讲师素材列表", "GET", "/api/ip/materials", "获取素材"],
    ["合规授权确认", "POST", "/api/ip/consent", "克隆前授权"],
]
story.append(make_table(["接口", "方法", "路径", "说明"], if2_rows, [70, 50, 165, 175], variant=True))
story.append(Paragraph("表7.3　阶段二接口清单（增量）", styles["CaptionStyle"]))

story.append(H("s", "7.5 外部依赖"))
story.extend(bullet([
    "LLM模型：Qwen2.5 14B（开源，私有部署）",
    "声音克隆：GPT-SoVITS / CosyVoice（开源，私有部署）",
    "数字人克隆：需采购厂商私有化授权（科大讯飞/硅基智能/商汤等），年费约10-20万",
]))

story.append(H("s", "7.6 交付物清单"))
story.extend(deliver_list([
    "Flutter端讲师IP功能（文案生成/声音管理/数字人/短视频合成）",
    "LLM推理服务部署（Qwen2.5 14B + OpenAI兼容API）",
    "GPT-SoVITS声音克隆服务部署",
    "数字人厂商SDK对接模块",
    "ffmpeg短视频合成流水线",
    "10个API接口（增量）",
    "四端打包（.exe/.ipa/.apk/Web）",
]))
story.append(S(10))
story.append(B("<b>预估工期：4-5周 | 交付标准：讲师可独立完成文案→声音→数字人→短视频全流程，覆盖SRS 3.5全部5个需求点。</b>"))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第八章：阶段三 SRS（前端业务）
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第八章　阶段三 SRS：前端业务模块"))
story.append(HR())

story.append(H("s", "8.1 阶段目标"))
story.append(B("构建市场部子系统和招投标合同中心子系统。移动端特别适合市场专员外勤场景：客户走访记录、现场拍照、语音备忘录。招投标模块在PC端用于合同编辑和知识库管理。所有文件资源均接入阶段一通用预览服务。"))

story.append(H("s", "8.2 市场部子系统功能需求"))
f3a_rows = [
    ["F3.1", "客户管理", "资料存档、行为采集", "结构化存储、多维度分析"],
    ["F3.2", "客户管理", "满意度跟踪、流失预警", "阈值配置+自动预警"],
    ["F3.3", "客户管理", "需求预测建模", "LLM分析→预测报告"],
    ["F3.4", "营销方案制作", "一键生成路演方案", "模板+客户画像→LLM"],
    ["F3.5", "项目跟进", "实时汇总项目资料", "多源资料自动聚合"],
    ["F3.6", "项目跟进", "自动生成项目简报", "LLM多文档摘要"],
    ["F3.7", "社群运营", "客户互动行为分析", "NLP语义分析"],
    ["F3.8", "社群运营", "社群活跃度监测", "指标可视化仪表盘"],
    ["F3.9", "社群运营", "智能问答机器人", "RAG知识库+对话"],
]
story.append(make_table(["编号", "功能模块", "功能点", "AI能力"], f3a_rows, [42, 85, 158, 175], variant=True))
story.append(Paragraph("表8.1　市场部子系统功能需求", styles["CaptionStyle"]))

story.append(H("s", "8.3 招投标子系统功能需求"))
f3b_rows = [
    ["F3.10", "合同模板管理", "模板CRUD + 字段变量定义"],
    ["F3.11", "AI合同生成", "模板+参数→LLM生成 + 版本归档 + 差异对比"],
    ["F3.12", "知识库管理", "材料归集 + 公司/同业案例库 + 标签体系"],
    ["F3.13", "知识库检索", "Elasticsearch全文检索 + 相似案例推荐"],
    ["F3.14", "招投标流程", "阶段管理 + 节点优化 + 合同归档"],
    ["F3.15", "供应商师资库", "师资归集 + 一键检索 + 课程智能匹配"],
]
story.append(make_table(["编号", "功能", "详细描述"], f3b_rows, [50, 90, 320], variant=True))
story.append(Paragraph("表8.2　招投标子系统功能需求", styles["CaptionStyle"]))

story.append(H("s", "8.4 平台适配要点"))
story.extend(bullet([
    "PC端（.exe）：复杂表格、批量操作、键盘快捷键、合同文档对比编辑",
    "移动端（.ipa/.apk）：外勤走访记录、拍照上传、语音备忘录、消息推送",
    "所有附件/文档/方案/合同/简报均接入阶段一通用权限预览服务",
    "所有AI生成内容支持人工二次编辑",
]))

story.append(H("s", "8.5 接口需求（增量）"))
if3_rows = [
    ["接口", "方法", "路径", "说明"],
    ["客户管理", "GET/POST", "/api/marketing/customers[/{id}]", "客户CRUD"],
    ["生成方案", "POST", "/api/marketing/proposals/generate", "LLM路演方案"],
    ["生成简报", "POST", "/api/marketing/briefings/generate", "LLM项目简报"],
    ["社群分析", "GET", "/api/marketing/community/analytics", "活跃度+情感"],
    ["问答机器人", "POST", "/api/marketing/qa/ask", "RAG问答"],
    ["合同模板", "GET/POST", "/api/bidding/templates[/{id}]", "模板管理"],
    ["生成合同", "POST", "/api/bidding/contracts/generate", "LLM合同"],
    ["知识库搜索", "GET", "/api/bidding/knowledge/search?q=", "ES检索"],
    ["供应商搜索", "GET", "/api/bidding/suppliers/search?q=", "师资检索"],
    ["课程匹配", "POST", "/api/bidding/suppliers/match", "智能匹配"],
]
story.append(make_table(["接口", "方法", "路径", "说明"], if3_rows, [65, 70, 165, 160], variant=True))
story.append(Paragraph("表8.3　阶段三接口清单（增量）", styles["CaptionStyle"]))

story.append(H("s", "8.6 交付物清单"))
story.extend(deliver_list([
    "Flutter端市场部功能（客户/方案/跟进/社群4模块+仪表盘）",
    "Flutter端招投标功能（合同/知识库/流程/供应商4模块）",
    "Elasticsearch全文检索部署",
    "RAG知识库问答系统部署",
    "10个API接口（增量）",
    "四端打包更新",
]))
story.append(S(10))
story.append(B("<b>预估工期：5-6周 | 交付标准：市场部+招投标全线可用，覆盖SRS 3.2.1和3.2.2全部9个需求点。</b>"))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第九章：阶段四 SRS（中台+后端）
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第九章　阶段四 SRS：中台与后端模块"))
story.append(HR())

story.append(H("s", "9.1 阶段目标"))
story.append(B("构建项目管理中台、人力资源中心和财务中心，打通从「前端业务→中台项目管理→后端HR/财务」的全链路数据流转。移动端支持项目经理现场走访、HR面试安排，PC端支持中台管控和财务管理。"))

story.append(H("s", "9.2 项目管理中台功能需求"))
f4a_rows = [
    ["F4.1", "项目方案", "上传材料→AI生成方案", "LLM方案生成"],
    ["F4.2", "行事历管理", "日历视图+里程碑+提醒", "—"],
    ["F4.3", "走访日志", "移动端录音/文本→AI生成点评", "AI点评生成"],
    ["F4.4", "分析报表", "上传数据→一键生成图表报表", "数据可视化"],
    ["F4.5", "培训课件", "知识库→AI生成课件（PPT/PDF）", "LLM课件生成"],
    ["F4.6", "课件管理", "课件+照片+签到表上传+版本管理", "—"],
    ["F4.7", "评估总结", "全量材料→自动生成总结报告", "LLM报告生成"],
    ["F4.8", "客户反馈", "图文上传+反馈收集", "—"],
    ["F4.9", "结算管控", "检索结算材料+标准管理+版本控制", "—"],
]
story.append(make_table(["编号", "功能", "AI能力"], f4a_rows, [42, 200, 90, 128], variant=True))
story.append(Paragraph("表9.1　项目管理中台功能需求", styles["CaptionStyle"]))

story.append(H("s", "9.3 人力资源中心功能需求"))
f4b_rows = [
    ["F4.10", "简历获取", "上传+OCR解析", "OCR"],
    ["F4.11", "AI筛选匹配", "简历vs岗位→LLM匹配评分", "LLM匹配"],
    ["F4.12", "面试安排", "日历自动排期+通知推送", "—"],
    ["F4.13", "员工信息管理", "档案CRUD+字段自定义", "—"],
    ["F4.14", "流程审批", "审批流引擎（请假/报销/转正）", "—"],
    ["F4.15", "师资管理库", "全量师资标签检索+资质归档", "标签化检索"],
]
story.append(make_table(["编号", "功能", "AI能力"], f4b_rows, [42, 200, 90, 128], variant=True))
story.append(Paragraph("表9.2　人力资源中心功能需求", styles["CaptionStyle"]))

story.append(H("s", "9.4 财务中心功能需求"))
f4c_rows = [
    ["F4.16", "结算数据对接", "中台→财务", "—"],
    ["F4.17", "费用核算", "金额计算+审批", "—"],
    ["F4.18", "凭证归档", "上传+结算关联", "—"],
    ["F4.19", "权限预览", "凭证仅财务人员可预览", "复用阶段一"],
]
story.append(make_table(["编号", "功能", "AI能力"], f4c_rows, [42, 200, 90, 128], variant=True))
story.append(Paragraph("表9.3　财务中心功能需求", styles["CaptionStyle"]))

story.append(H("s", "9.5 数据流转"))
story.extend(bullet([
    "市场部项目 → 中台项目管理（项目方案、材料）",
    "招投标合同 → 中台项目管理（合同归档）",
    "中台项目管理 → 财务中心（结算数据）",
    "中台师资使用 → HR师资库（师资同步）",
    "所有模块文件 → 通用预览服务（权限校验+预览渲染）",
]))

story.append(H("s", "9.6 接口需求（增量）"))
if4_rows = [
    ["接口", "方法", "路径", "说明"],
    ["项目方案生成", "POST", "/api/pm/proposals/generate", "LLM方案"],
    ["行事历CRUD", "GET/POST", "/api/pm/calendar[/{id}]", "日历管理"],
    ["AI生成点评", "POST", "/api/pm/reviews/generate", "录音→点评"],
    ["生成报表", "POST", "/api/pm/reports/generate", "数据→图表"],
    ["课件生成", "POST", "/api/pm/courseware/generate", "LLM课件"],
    ["生成总结报告", "POST", "/api/pm/summaries/generate", "全量→总结"],
    ["结算检索", "GET", "/api/pm/settlements/search", "按讲师/项目"],
    ["简历上传+OCR", "POST", "/api/hr/resumes/upload", "OCR解析"],
    ["简历匹配", "POST", "/api/hr/resumes/match", "LLM评分"],
    ["员工档案", "GET/POST", "/api/hr/employees[/{id}]", "员工管理"],
    ["审批流", "POST/PUT", "/api/hr/approvals[/{id}]", "审批引擎"],
    ["师资库检索", "GET", "/api/hr/instructors/search", "标签检索"],
    ["结算同步", "POST", "/api/finance/settlements/sync", "中台→财务"],
    ["费用核算", "POST", "/api/finance/accounting", "核算计算"],
    ["凭证归档", "POST", "/api/finance/vouchers", "上传归档"],
]
story.append(make_table(["接口", "方法", "路径", "说明"], if4_rows, [70, 65, 160, 165], variant=True))
story.append(Paragraph("表9.4　阶段四接口清单（增量）", styles["CaptionStyle"]))

story.append(H("s", "9.7 交付物清单"))
story.extend(deliver_list([
    "Flutter端项目管理中台（方案/过程/课件/评估/结算5模块）",
    "Flutter端HR中心（招募/人事/师资库3模块）",
    "Flutter端财务中心（结算/核算/凭证3模块）",
    "审批流引擎",
    "15个API接口（增量）",
    "四端打包更新",
]))
story.append(S(10))
story.append(B("<b>预估工期：5-6周 | 交付标准：三级架构闭环，覆盖SRS 3.3、3.4.1、3.4.2全部14个需求点。</b>"))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 第十章：阶段五（联调部署上线）
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "第十章　阶段五：联调部署与上线"))
story.append(HR())

story.append(H("s", "10.1 阶段目标"))
story.append(B("完成全系统联调、非功能需求达标、安全加固、四端打包签名分发和私有化部署，交付生产就绪系统。"))

story.append(H("s", "10.2 迭代规划"))
f5_rows = [
    ["5.1 系统联调", "前端-中台同步联调\n中台-财务/人力流转联调\n全模块权限校验一致性测试\n51个需求点逐条验收\n四端UI/UX一致性检查", "1周", "全流程回归测试报告"],
    ["5.2 性能+安全", "响应时间/并发/加载压测优化\nTLS+AES加密验证\n审计日志完整性验证\n克隆合规授权校验\nWindows/Mac/iOS/Android兼容性", "1-1.5周", "性能测试报告\n安全检查清单"],
    ["5.3 打包分发", "Windows .exe签名+安装包\nAndroid .apk签名\niOS .ipa企业证书签名分发\nWeb部署包构建", "0.5周", "四端安装包\n分发说明文档"],
    ["5.4 私有化部署", "部署架构方案\nDocker镜像构建+生产配置\n安装/配置/运维/备份恢复手册\n管理员培训", "1周", "部署手册\n运维手册\n系统交接文档"],
]
story.append(make_table(["迭代", "内容", "周期", "关键产出"], f5_rows, [65, 220, 55, 120], variant=True))
story.append(Paragraph("表10.1　阶段五迭代规划", styles["CaptionStyle"]))

story.append(H("s", "10.3 非功能需求验收清单"))
nf5_rows = [
    ["8.1", "AI生成 ≤10s", "文案/方案/简报/合同生成10s内", "JMeter压测"],
    ["8.2", "知识库并发 ≥50", "50并发检索响应≤2s", "JMeter"],
    ["8.3", "音视频克隆 ≤30s", "语音合成+数字人口播≤30s", "计时测试"],
    ["8.4", "文档预览 ≤2s", "Word/Excel/PDF首屏≤2s", "计时测试"],
    ["8.5", "图片预览 ≤1.5s", "JPG/PNG加载≤1.5s", "计时测试"],
    ["8.6", "视频首帧 ≤3s", "MP4流式播放首帧≤3s", "计时测试"],
    ["8.7", "数据加密", "传输TLS+存储AES-256", "安全扫描"],
    ["8.8", "审计完整性", "全操作留痕+水印溯源", "功能验证"],
    ["8.9", "克隆合规", "授权校验+防滥用", "功能验证"],
    ["8.12", "四端兼容", "Win10/11+iOS15++Android10++Web", "人工测试"],
    ["8.12", "文件格式", "Word/Excel/PDF/MP4/JPG/MP3", "人工测试"],
]
story.append(make_table(["编号", "指标", "验收标准", "方法"], nf5_rows, [38, 100, 180, 80], variant=True))
story.append(Paragraph("表10.2　非功能需求验收清单", styles["CaptionStyle"]))

story.append(H("s", "10.4 交付物清单"))
story.extend(deliver_list([
    "全系统联调测试报告",
    "性能测试报告（含压测数据）",
    "安全检查报告",
    "生产环境Docker Compose配置",
    "Windows .exe签名安装包",
    "iOS .ipa（企业证书分发）",
    "Android .apk签名安装包",
    "Web部署包",
    "部署安装手册",
    "运维手册（备份恢复/监控/日志）",
    "系统管理员培训材料",
    "完整源码交付（含版本管理仓库）",
    "系统交接确认书",
]))
story.append(S(10))
story.append(B("<b>预估工期：3-4周 | 交付标准：51个需求点全部验收通过，四端App分发就绪，系统上线运行。</b>"))
story.append(PageBreak())

# ═══════════════════════════════════════════════════════════
# 附录：全系统需求追溯矩阵
# ═══════════════════════════════════════════════════════════
story.append(H("chapter", "附录　全系统需求追溯矩阵"))
story.append(HR())

matrix = [
    ["1.1", "预览触发前权限校验+拦截+提示", "通用预览", "阶段一", "1.3"],
    ["1.2", "多格式文档/图片/音视频页内预览", "通用预览", "阶段一", "1.3"],
    ["1.3", "水印溯源+禁止右键/截图", "通用预览", "阶段一", "1.3"],
    ["1.4", "分级下载（仅授权用户）", "通用预览", "阶段一", "1.3"],
    ["1.5", "管理员分级权限配置UI", "通用预览", "阶段一", "1.3"],
    ["1.6", "权限状态标注（可预览/无权限）", "通用预览", "阶段一", "1.3"],
    ["1.7", "流式分片加载", "通用预览", "阶段一", "1.3"],
    ["2.1", "客户管理（资料/行为/满意度/预警/预测）", "市场部", "阶段三", "3.1"],
    ["2.2", "营销方案一键生成", "市场部", "阶段三", "3.1"],
    ["2.3", "项目跟进（资料汇总+简报生成）", "市场部", "阶段三", "3.2"],
    ["2.4", "社群运营（分析+活跃度+问答机器人）", "市场部", "阶段三", "3.2"],
    ["2.5", "市场部所有文件权限预览配套", "市场部", "阶段三", "3.1-3.2"],
    ["3.1", "合同AI生成+版本归档+预览", "招投标", "阶段三", "3.3"],
    ["3.2", "知识库管理+案例检索+预览", "招投标", "阶段三", "3.3"],
    ["3.3", "流程管理+归档+预览", "招投标", "阶段三", "3.3"],
    ["3.4", "供应商师资库+课程匹配+预览", "招投标", "阶段三", "3.3"],
    ["4.1", "项目方案AI生成+预览", "项目管理", "阶段四", "4.1"],
    ["4.2", "过程管理（行事历+日志+AI点评+报表）", "项目管理", "阶段四", "4.1"],
    ["4.3", "培训课件（AI生成+上传+预览）", "项目管理", "阶段四", "4.2"],
    ["4.4", "项目评估总结+客户反馈+预览", "项目管理", "阶段四", "4.2"],
    ["4.5", "结算管控（检索+标准管理+预览）", "项目管理", "阶段四", "4.2"],
    ["5.1", "招募系统（简历获取+AI筛选+面试安排）", "人力资源", "阶段四", "4.3"],
    ["5.2", "人事管理（数字化+审批+预览）", "人力资源", "阶段四", "4.3"],
    ["5.3", "师资管理库（标签检索+预览）", "人力资源", "阶段四", "4.3"],
    ["6.1", "结算数据对接", "财务中心", "阶段四", "4.4"],
    ["6.2", "费用核算", "财务中心", "阶段四", "4.4"],
    ["6.3", "凭证归档+预览", "财务中心", "阶段四", "4.4"],
    ["7.1", "公众号/朋友圈AI文案生成", "讲师IP", "阶段二", "2.1"],
    ["7.2", "1分钟短视频AI生产", "讲师IP", "阶段二", "2.3"],
    ["7.3", "声音克隆", "讲师IP", "阶段二", "2.2"],
    ["7.4", "数字人克隆", "讲师IP", "阶段二", "2.3"],
    ["7.5", "讲师素材权限预览", "讲师IP", "阶段二", "2.1-2.3"],
    ["8.1", "AI生成≤10s", "非功能", "阶段五", "5.2"],
    ["8.2", "知识库并发≥50", "非功能", "阶段五", "5.2"],
    ["8.3", "音视频克隆≤30s", "非功能", "阶段五", "5.2"],
    ["8.4", "文档预览≤2s", "非功能", "阶段五", "5.2"],
    ["8.5", "图片预览≤1.5s", "非功能", "阶段五", "5.2"],
    ["8.6", "视频首帧≤3s", "非功能", "阶段五", "5.2"],
    ["8.7", "数据加密+分级权限+审计", "非功能", "阶段五", "5.2"],
    ["8.8", "水印溯源+审计日志", "非功能", "阶段五", "5.2"],
    ["8.9", "克隆合规授权校验", "非功能", "阶段五", "5.2"],
    ["8.10", "全模块可视化+AI配置向导", "非功能", "阶段五", "5.2"],
    ["8.11", "生成内容二次编辑", "非功能", "阶段五", "5.2"],
    ["8.12", "PC+移动端+主流格式兼容", "非功能", "阶段五", "5.2"],
    ["9.1", "前端-中台数据同步接口", "接口", "阶段五", "5.1"],
    ["9.2", "中台-财务/人力流转接口", "接口", "阶段五", "5.1"],
    ["9.3", "权限校验统一接口", "接口", "阶段五", "5.1"],
    ["9.4", "文件预览渲染接口", "接口", "阶段五", "5.1"],
    ["9.5", "AI大模型调用接口", "接口", "阶段五", "5.1"],
    ["9.6", "音视频克隆第三方接口", "接口", "阶段五", "5.1"],
    ["9.7", "OA/CRM系统对接接口", "接口", "阶段五", "5.1"],
]
story.append(make_table(
    ["编号", "需求描述", "模块", "阶段", "迭代"],
    matrix, [38, 160, 65, 60, 58], variant=True,
))
story.append(Paragraph("附表1　全系统51个需求点完整追溯矩阵", styles["CaptionStyle"]))

story.append(PageBreak())

# ─── 末页 ────────────────────────────────────────────────
story.append(S(80))
story.append(Paragraph("— 报告结束 —", styles["CoverSubtitle"]))
story.append(S(16))
story.append(Paragraph(f"生成日期：{datetime.now().strftime('%Y年%m月%d日 %H:%M')}", styles["SmallNote"]))
story.append(Paragraph("Flutter全端架构 · 一套代码四端交付", styles["SmallNote"]))
story.append(Paragraph("Windows .exe | iOS .ipa | Android .apk | Web", styles["SmallNote"]))

# ─── 生成 ────────────────────────────────────────────────
doc.build(story)
print(f"PDF report generated: {os.path.abspath(output_path)}")
