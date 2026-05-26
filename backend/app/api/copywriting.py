import uuid
import re
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_db
from app.models import User, CopyTemplate, CopyHistory
from app.security import get_current_user
from app.services.llm.router import get_llm
from app.services.llm.base import LLMConfig
from app.services.audit import log as audit_log

try:
    import markdown as md
    _HAS_MD = True
except ImportError:
    md = None  # type: ignore[assignment]
    _HAS_MD = False

PLATFORM_TYPES = {"wechat", "moments", "xiaohongshu", "douyin", "other"}

PLATFORM_NAMES = {
    "wechat": "公众号",
    "moments": "朋友圈",
    "xiaohongshu": "小红书",
    "douyin": "抖音",
    "other": "通用",
}

_TONE_PALETTE = {
    "专业严谨": {"primary": "#1a73e8", "secondary": "#1557b0", "bg": "#f8f9fc", "card_bg": "#ffffff", "accent": "#4285f4"},
    "轻松活泼": {"primary": "#f97316", "secondary": "#ea580c", "bg": "#fffbf5", "card_bg": "#ffffff", "accent": "#fb923c"},
    "温情故事": {"primary": "#e85382", "secondary": "#d43d6a", "bg": "#fdf6f8", "card_bg": "#ffffff", "accent": "#f472a6"},
    "悬念吸引": {"primary": "#6c5ce7", "secondary": "#4834d4", "bg": "#f8f7ff", "card_bg": "#ffffff", "accent": "#8b7cf6"},
    "促销紧迫": {"primary": "#e74c3c", "secondary": "#c0392b", "bg": "#fffafa", "card_bg": "#ffffff", "accent": "#fc5c65"},
    "幽默风趣": {"primary": "#10b981", "secondary": "#059669", "bg": "#f5fdf9", "card_bg": "#ffffff", "accent": "#34d399"},
}


def _build_css(tone: str) -> str:
    p = _TONE_PALETTE.get(tone, _TONE_PALETTE["专业严谨"])
    primary = p["primary"]
    secondary = p["secondary"]
    bg = p["bg"]
    card_bg = p["card_bg"]
    accent = p["accent"]

    return f"""<style>
  *{{margin:0;padding:0;box-sizing:border-box}}
  body{{
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;
    background:linear-gradient(180deg,{bg} 0%,{bg}ee 100%);
    color:#2d3436;line-height:1.8;padding:0 16px 40px;
  }}
  .article{{max-width:680px;margin:0 auto;padding-top:28px}}
  .header-card{{
    background:linear-gradient(135deg,{secondary} 0%,{primary} 60%,{accent} 100%);
    border-radius:20px;padding:32px 28px;margin-bottom:28px;
    color:#fff;position:relative;overflow:hidden;
  }}
  .header-card::before{{
    content:"";position:absolute;top:-50px;right:-50px;
    width:140px;height:140px;border-radius:50%;
    background:rgba(255,255,255,.06);
  }}
  .header-card::after{{
    content:"";position:absolute;bottom:-40px;left:-40px;
    width:100px;height:100px;border-radius:50%;
    background:rgba(255,255,255,.04);
  }}
  .header-card h1{{font-size:26px;font-weight:800;margin-bottom:8px;position:relative;z-index:1}}
  .header-card .subtitle{{font-size:13px;opacity:.7;position:relative;z-index:1}}
  h2{{
    font-size:18px;font-weight:700;color:#1a1a2e;
    margin:28px 0 14px;padding-left:14px;
    border-left:3px solid {primary};
  }}
  h3{{font-size:16px;font-weight:700;color:#2d3436;margin:20px 0 10px}}
  p{{margin:10px 0;font-size:15px;color:#3d3d3d;line-height:1.85}}
  strong{{color:{primary};font-weight:700}}
  blockquote{{
    background:linear-gradient(135deg,{primary}08,{accent}08);
    border-radius:12px;padding:18px 20px 18px 44px;margin:18px 0;
    border-left:4px solid {primary};
    font-size:15px;color:#4a4a6a;line-height:1.75;position:relative;
  }}
  blockquote::before{{
    content:""\\201C"";position:absolute;top:6px;left:14px;
    font-size:32px;color:{primary};opacity:.35;font-family:Georgia,serif;
  }}
  blockquote p{{color:inherit}}
  hr{{border:0;height:1px;background:linear-gradient(90deg,transparent,{primary}30,transparent);margin:32px 0}}
  ul,ol{{margin:12px 0 12px 20px}}
  li{{font-size:15px;color:#3d3d3d;margin:6px 0;line-height:1.75}}
  .section-card{{
    background:{card_bg};border-radius:16px;
    padding:24px;margin:20px 0;
    box-shadow:0 2px 16px rgba(0,0,0,.04);
  }}
  .section-card h2{{margin-top:0}}
  .img-placeholder{{
    margin:20px 0;border-radius:14px;overflow:hidden;
    background:{card_bg};box-shadow:0 2px 12px rgba(0,0,0,.05);
  }}
  .img-placeholder .img-box{{
    position:relative;width:100%;display:flex;align-items:center;
    justify-content:center;flex-direction:column;gap:10px;
    background:linear-gradient(135deg,{primary}05,{accent}07);
    border:2px dashed {primary}20;
  }}
  .img-placeholder .img-box .img-icon{{font-size:44px;opacity:.3}}
  .img-placeholder .img-box .img-label{{
    font-size:15px;font-weight:700;color:{primary};
  }}
  .img-placeholder .img-box .img-desc{{
    font-size:12px;color:#8899aa;text-align:center;
    padding:0 16px 16px;line-height:1.5;
  }}
  .img-placeholder .img-meta{{
    display:flex;align-items:center;gap:8px;
    padding:8px 16px;font-size:11px;color:#8899aa;
    background:linear-gradient(90deg,{primary}04,transparent);
  }}
  .img-placeholder .img-meta .dot{{
    width:6px;height:6px;border-radius:50%;background:{primary};opacity:.5;
  }}
  .ratio-16-9 .img-box{{aspect-ratio:16/9}}
  .ratio-4-3 .img-box{{aspect-ratio:4/3}}
  .ratio-1-1 .img-box{{aspect-ratio:1/1}}
  .ratio-3-4 .img-box{{aspect-ratio:3/4}}
  .cta-card{{
    background:linear-gradient(135deg,{primary},{secondary});
    border-radius:18px;padding:28px 24px;margin:32px 0 20px;
    color:#fff;text-align:center;
  }}
  .cta-card p{{color:rgba(255,255,255,.9);font-size:15px}}
  .cta-card strong{{color:#fff}}
  .btn-row{{margin-top:18px;display:flex;gap:10px;justify-content:center;flex-wrap:wrap}}
  .btn{{
    display:inline-block;padding:8px 20px;border-radius:20px;
    font-size:13px;font-weight:600;text-decoration:none;
    background:rgba(255,255,255,.2);color:#fff;
    backdrop-filter:blur(10px);cursor:pointer;
  }}
  .color-scheme{{display:flex;gap:12px;flex-wrap:wrap;margin:14px 0}}
  .color-dot{{display:flex;align-items:center;gap:6px;font-size:12px;color:#666}}
  .color-dot span{{width:24px;height:24px;border-radius:50%;display:inline-block;box-shadow:0 2px 4px rgba(0,0,0,.1)}}
  .footer-note{{text-align:center;font-size:12px;color:#999;margin-top:24px}}
</style>"""


def _strip_meta_sections(raw: str) -> str:
    """Remove 配图方案 and 排版配色建议 sections from markdown."""
    raw = re.sub(r'\n#{1,3}\s*\d*[\.\、]?\s*配图方案.*$', '', raw, flags=re.DOTALL)
    raw = re.sub(r'\n#{1,3}\s*\d*[\.\、]?\s*排版配色建议.*$', '', raw, flags=re.DOTALL)
    return raw.strip()

def _guess_aspect_ratio(desc: str) -> str:
    """Guess aspect ratio class from image description."""
    d = desc.lower()
    if '头图' in d or '16:9' in d or '封面' in d:
        return 'ratio-16-9'
    if '1:1' in d or '方形' in d or '产品图' in d:
        return 'ratio-1-1'
    if '3:4' in d or '引导' in d:
        return 'ratio-3-4'
    if '4:3' in d:
        return 'ratio-4-3'
    return 'ratio-16-9'  # default

def _md_to_html(raw: str, tone: str = "专业严谨") -> str:
    """Convert markdown to a beautiful, magazine-quality HTML article."""
    # Strip meta sections before converting
    raw = _strip_meta_sections(raw)
    if not raw or not _HAS_MD:
        return raw

    extensions = [
        "fenced_code",
        "tables",
        "nl2br",
        "sane_lists",
    ]
    try:
        html = md.markdown(raw, extensions=extensions, output_format="html5")  # type: ignore[union-attr]
    except Exception:
        return raw

    html = re.sub(r"</?code[^>]*>", "", html, flags=re.IGNORECASE)
    html = re.sub(r"</?pre[^>]*>", "", html, flags=re.IGNORECASE)
    html = re.sub(r"<hr\s*/?>", '<hr>', html)

    parts = html.split("<hr>")
    wrapped = []
    for part in parts:
        part = part.strip()
        if not part:
            continue
        if "cta-card" in part or "color-scheme" in part or "btn-row" in part:
            wrapped.append(part)
        else:
            wrapped.append(f'<div class="section-card">{part}</div>')

    body = "\n".join(wrapped)

    _icon = '\U0001F5BC'
    # [插图N] 配图说明：xxx → sized placeholder with description and meta
    body = re.sub(
        r'<p>\[插图(\d+)\]\s*配图说明[：:](.*?)</p>',
        lambda m: f'<div class="img-placeholder {_guess_aspect_ratio(m.group(2))}"><div class="img-box"><div class="img-icon">{_icon}</div><div class="img-label">插图{m.group(1)}</div><div class="img-desc">{m.group(2)}</div></div><div class="img-meta"><span class="dot"></span>配图说明</div></div>',
        body,
    )
    # [插图N] description → sized placeholder
    body = re.sub(
        r'<p>\[插图(\d+)\]\s*(.*?)</p>',
        lambda m: f'<div class="img-placeholder {_guess_aspect_ratio(m.group(2))}"><div class="img-box"><div class="img-icon">{_icon}</div><div class="img-label">插图{m.group(1)}</div><div class="img-desc">{m.group(2)}</div></div></div>',
        body,
    )
    # Bare [插图N]
    body = re.sub(
        r'\[插图(\d+)\]',
        lambda m: f'<div class="img-placeholder ratio-16-9"><div class="img-box"><div class="img-icon">{_icon}</div><div class="img-label">插图{m.group(1)}</div></div></div>',
        body,
    )

    full = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
{_build_css(tone)}
</head>
<body>
<div class="article">
{body}
<div class="footer-note">AI 智能生成 · 可直接粘贴到公众号编辑器</div>
</div>
</body>
</html>"""

    return full

router = APIRouter(prefix="/copy", tags=["copywriting"])


class TemplateCreate(BaseModel):
    name: str
    platform_type: str = "wechat"
    template_content: str
    system_prompt: str = ""


class TemplateUpdate(BaseModel):
    name: str | None = None
    platform_type: str | None = None
    template_content: str | None = None
    system_prompt: str | None = None


class GenerateRequest(BaseModel):
    template_id: str
    params: dict = {}


# ── Template CRUD ──

@router.get("/templates")
async def list_templates(
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(CopyTemplate).order_by(CopyTemplate.updated_at.desc())
    )
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(r.id),
                "name": r.name,
                "platform_type": r.platform_type,
                "template_content": r.template_content,
                "system_prompt": r.system_prompt,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "updated_at": r.updated_at.isoformat() if r.updated_at else None,
            }
            for r in rows
        ]
    }


@router.post("/templates", status_code=201)
async def create_template(
    body: TemplateCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    if body.platform_type not in PLATFORM_TYPES:
        raise HTTPException(status_code=400, detail=f"不支持的平台类型: {body.platform_type}")

    tmpl = CopyTemplate(
        name=body.name,
        platform_type=body.platform_type,
        template_content=body.template_content,
        system_prompt=body.system_prompt,
        created_by=user.id,
    )
    db.add(tmpl)
    await db.commit()
    await db.refresh(tmpl)
    return {"id": str(tmpl.id)}


@router.put("/templates/{template_id}")
async def update_template(
    template_id: str,
    body: TemplateUpdate,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(CopyTemplate).where(CopyTemplate.id == uuid.UUID(template_id))
    )
    tmpl = result.scalar_one_or_none()
    if not tmpl:
        raise HTTPException(status_code=404, detail="模板不存在")

    if body.name is not None:
        tmpl.name = body.name
    if body.platform_type is not None:
        if body.platform_type not in PLATFORM_TYPES:
            raise HTTPException(status_code=400, detail=f"不支持的平台类型: {body.platform_type}")
        tmpl.platform_type = body.platform_type
    if body.template_content is not None:
        tmpl.template_content = body.template_content
    if body.system_prompt is not None:
        tmpl.system_prompt = body.system_prompt

    await db.commit()
    return {"id": str(tmpl.id)}


@router.delete("/templates/{template_id}")
async def delete_template(
    template_id: str,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(CopyTemplate).where(CopyTemplate.id == uuid.UUID(template_id))
    )
    tmpl = result.scalar_one_or_none()
    if not tmpl:
        raise HTTPException(status_code=404, detail="模板不存在")

    await db.delete(tmpl)
    await db.commit()
    return {"message": "已删除"}


# ── Generate (direct, no template required) ──

class GenerateDirectRequest(BaseModel):
    platform_type: str = "wechat"
    topic: str = ""
    core_info: str = ""
    target_audience: str = ""
    tone: str = "专业严谨"
    purpose: str = "品牌宣传"


SYSTEM_PROMPT = """# 角色设定
你现在是一位拥有百万粉丝操盘经验的资深微信公众号爆款编辑，精通受众心理学，擅长撰写高点击率、高转化率、情绪价值拉满的微信推文。你同时具备专业的视觉审美能力，能够为每一篇文章设计精准的配图方案。

# 任务描述
请根据我提供的【核心信息】，撰写一篇完整的微信公众号文章。你的输出将直接复制粘贴到公众号编辑器中发布，因此需要严格按照公众号的文章排版格式输出，并设计配套的图片方案。

# 公众号排版格式规范
- 正文使用 14-15px 字号风格，小标题使用 16-18px 风格，标注使用 12px 风格
- 重要数据、核心观点用 **粗体** 突出
- 金句使用 <blockquote> 引用块样式（不要用"金句："前缀）
- 段落之间空一行，保持呼吸感
- 每个段落不超过 5 行，适配手机阅读
- 使用 Emoji 作为视觉锚点引导阅读
- 全文色系保持一致（默认 #333 正文色，重点色根据主题选择）

# 内容结构与要求

## 1. 爆款标题推荐
5 个不同风格的标题（引发好奇型 / 痛点共鸣型 / 干货盘点型 / 情绪价值型 / 反常识型）

## 2. 正文（直接可发布格式）
每个大段之间用 --- 分隔。

**[插图] 配图说明：xxx** → 标记图片插入位置（用方括号包裹）

**引言**
- 痛点切入或悬念开头，前200字抓住读者
- 3-4 段短句，每段不超过3行
- 引言后插入第一张配图

**核心卖点展开**
- 3-4 个小标题段落，每段包含：
  - 小标题：Emoji + 核心卖点（加粗）
  - 正文：短句展开，口语化但有专业度
  - 引用块：1 句精华，用 <blockquote> 包裹，适合截图转发
  - 每个核心卖点后插入一张配图

**结尾 CTA**
- 全文升华总结（2-3句）
- 互动话题（引导评论区讨论）
- 行动号召：引导点赞、在看、分享、关注
- 结尾插入引导关注/转发图

## 3. 配图方案（文末单独列出）
为全文设计 3-5 张配图，每张给出：
- 插图编号：对应文中的 [插图] 位置
- 图片类型：头图/信息图/场景图/产品图/引导图
- 画面描述：详细的画面内容（含色调、构图、元素），这段描述可直接作为 AI 生图提示词
- 推荐尺寸：宽高比（如 16:9、1:1、3:4）

## 4. 排版配色建议
推荐色系（主色/辅色/强调色/正文色），用于公众号后台设置全文配色。

# 重要规则
- 只撰写与用户指定的产品/主题直接相关的内容，绝不偏离主题
- 不要在文案中编造产品名称，使用用户提供的准确产品名
- 输出即成品，可直接复制粘贴到公众号编辑器后台
- 请直接开始撰写，不要问问题，不要说"好的，请提供更多信息"

请深呼吸，发挥你最顶尖的文案水平，开始撰写！"""


def _build_generate_prompt(body: GenerateDirectRequest) -> str:
    platform_name = PLATFORM_NAMES.get(body.platform_type, body.platform_type)
    lines = [
        f"# 目标受众与文章基调",
        f"- 目标受众：{body.target_audience or '职场白领'}",
        f"- 文章基调：{body.tone or '专业严谨'}",
        f"- 核心目的：{body.purpose or '品牌宣传'}",
        f"- 发布平台：{platform_name}",
        f"",
        f"# 我的【核心信息】如下：",
        f"产品/主题：{body.topic}",
        f"{body.core_info}",
    ]
    return "\n".join(lines)


@router.post("/generate-direct")
async def generate_copy_direct(
    body: GenerateDirectRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    user_prompt = _build_generate_prompt(body)
    llm = get_llm()

    try:
        resp = await llm.generate(
            system_prompt=SYSTEM_PROMPT,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=0.8, max_tokens=4096),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM 调用失败: {e}")

    await audit_log(
        db, user, "copy_generate", "copywriting", None,
        body.topic, "success", f"model={resp.model}", request=request,
    )

    # save to history for traceability
    history = CopyHistory(
        user_id=user.id,
        platform_type=body.platform_type,
        topic=body.topic,
        core_info=body.core_info,
        target_audience=body.target_audience,
        tone=body.tone,
        purpose=body.purpose,
        content=resp.content,
        model=resp.model,
    )
    db.add(history)
    await db.commit()
    await db.refresh(history)

    return {
        "id": str(history.id),
        "content": resp.content,
        "content_html": _md_to_html(resp.content, tone=body.tone),
        "model": resp.model,
        "usage": resp.usage,
    }


# ── History ──


@router.get("/history")
async def list_history(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
    limit: int = 50,
    offset: int = 0,
):
    query = select(CopyHistory).order_by(CopyHistory.created_at.desc())
    if user.role != "admin":
        query = query.where(CopyHistory.user_id == user.id)

    result = await db.execute(query.offset(offset).limit(limit))
    rows = result.scalars().all()
    return {
        "items": [
            {
                "id": str(r.id),
                "platform_type": r.platform_type,
                "topic": r.topic,
                "core_info": r.core_info,
                "target_audience": r.target_audience,
                "tone": r.tone,
                "purpose": r.purpose,
                "content_preview": r.content[:200] if r.content else "",
                "model": r.model,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ],
        "total": len(rows),
    }


@router.get("/history/{history_id}")
async def get_history(
    history_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(CopyHistory).where(CopyHistory.id == uuid.UUID(history_id))
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="记录不存在")
    if record.user_id != user.id and user.role != "admin":
        raise HTTPException(status_code=403, detail="无权查看此记录")

    return {
        "id": str(record.id),
        "platform_type": record.platform_type,
        "topic": record.topic,
        "core_info": record.core_info,
        "target_audience": record.target_audience,
        "tone": record.tone,
        "purpose": record.purpose,
        "content": record.content,
        "content_html": _md_to_html(record.content, tone=record.tone),
        "model": record.model,
        "created_at": record.created_at.isoformat() if record.created_at else None,
    }


class HistoryUpdate(BaseModel):
    topic: str | None = None
    content: str | None = None


@router.put("/history/{history_id}")
async def update_history(
    history_id: str,
    body: HistoryUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(CopyHistory).where(CopyHistory.id == uuid.UUID(history_id))
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="记录不存在")
    if record.user_id != user.id and user.role != "admin":
        raise HTTPException(status_code=403, detail="无权修改此记录")

    if body.topic is not None:
        record.topic = body.topic
    if body.content is not None:
        record.content = body.content

    await db.commit()
    return {
        "id": str(record.id),
        "content_html": _md_to_html(record.content, tone=record.tone) if record.content else "",
    }


@router.delete("/history/{history_id}")
async def delete_history(
    history_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(CopyHistory).where(CopyHistory.id == uuid.UUID(history_id))
    )
    record = result.scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="记录不存在")
    if record.user_id != user.id and user.role != "admin":
        raise HTTPException(status_code=403, detail="无权删除此记录")

    await db.delete(record)
    await db.commit()
    return {"message": "已删除"}


# ── Generate (template-based, legacy) ──

@router.post("/generate")
async def generate_copy(
    body: GenerateRequest,
    request: Request = None,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(CopyTemplate).where(CopyTemplate.id == uuid.UUID(body.template_id))
    )
    tmpl = result.scalar_one_or_none()
    if not tmpl:
        raise HTTPException(status_code=404, detail="模板不存在")

    user_prompt = tmpl.template_content
    for key, val in body.params.items():
        user_prompt = user_prompt.replace(f"{{{key}}}", str(val))

    system_prompt = tmpl.system_prompt or SYSTEM_PROMPT
    llm = get_llm()

    try:
        resp = await llm.generate(
            system_prompt=system_prompt,
            user_prompt=user_prompt,
            config=LLMConfig(temperature=0.7, max_tokens=4096),
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM 调用失败: {e}")

    await audit_log(
        db, user, "copy_generate", "copy_template", tmpl.id,
        tmpl.name, "success", f"model={resp.model}", request=request,
    )

    history = CopyHistory(
        user_id=user.id,
        platform_type=tmpl.platform_type,
        topic=tmpl.name,
        core_info=user_prompt[:500],
        content=resp.content,
        model=resp.model,
    )
    db.add(history)
    await db.commit()
    await db.refresh(history)

    return {
        "id": str(history.id),
        "content": resp.content,
        "content_html": _md_to_html(resp.content, tone="专业严谨"),
        "model": resp.model,
        "usage": resp.usage,
    }
