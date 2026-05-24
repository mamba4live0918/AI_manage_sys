from functools import lru_cache
from app.config import settings
from app.services.llm.base import BaseLLMProvider
from app.services.llm.openai_compatible import OpenAICompatibleProvider


@lru_cache()
def get_llm() -> BaseLLMProvider:
    """
    配置驱动的LLM路由 —— 改环境变量即可切换后端。

    开发阶段 (默认):
        LLM_PROVIDER=openai_compatible
        LLM_BASE_URL=https://api.deepseek.com/v1
        LLM_API_KEY=sk-xxx
        LLM_MODEL=deepseek-chat

    本地部署切换:
        LLM_BASE_URL=http://localhost:8001/v1
        LLM_API_KEY=not-needed
        LLM_MODEL=qwen2.5-14b

    所有后端只要兼容 OpenAI /v1/chat/completions 协议即可无缝切换。
    """
    provider = settings.LLM_PROVIDER

    if provider == "openai_compatible":
        return OpenAICompatibleProvider(
            base_url=settings.LLM_BASE_URL,
            api_key=settings.LLM_API_KEY,
            timeout=settings.LLM_TIMEOUT,
        )

    # 未来可扩展：provider == "anthropic" / "gemini" / "local_vllm" 等
    raise ValueError(f"Unknown LLM_PROVIDER: {provider}")
