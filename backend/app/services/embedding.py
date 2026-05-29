"""DeepSeek embedding API wrapper. Returns 768-dim vectors for semantic search."""
import logging
import httpx
from app.config import settings

logger = logging.getLogger(__name__)

# 中文约 1.5 chars/token，8192 tokens ≈ 12000 chars，留余量取 8000
_MAX_CHARS = 8000


async def get_embedding(text: str) -> list[float]:
    """Call DeepSeek /v1/embeddings. Returns empty list on failure (caller degrades to BM25)."""
    if not text or not text.strip():
        return []

    # 截断过长文本
    truncated = text.strip()[:_MAX_CHARS]

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(15.0)) as client:
            resp = await client.post(
                f"{settings.LLM_BASE_URL}/embeddings",
                headers={
                    "Authorization": f"Bearer {settings.LLM_API_KEY}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": settings.EMBEDDING_MODEL,
                    "input": truncated,
                },
            )
            resp.raise_for_status()
            data = resp.json()
            return data["data"][0]["embedding"]
    except Exception as e:
        logger.warning(f"Embedding API error: {e}")
        return []
