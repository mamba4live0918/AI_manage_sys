import httpx
from app.services.llm.base import BaseLLMProvider, LLMMessage, LLMResponse, LLMConfig
from typing import AsyncIterator


class OpenAICompatibleProvider(BaseLLMProvider):
    """OpenAI兼容协议适配器 —— 覆盖 免费API(DeepSeek/Groq) + 本地(vLLM/Ollama)"""

    def __init__(self, base_url: str, api_key: str, timeout: float = 60.0):
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self._client = httpx.AsyncClient(timeout=httpx.Timeout(timeout))

    def _build_payload(self, messages: list[LLMMessage], config: LLMConfig | None) -> dict:
        cfg = config or LLMConfig()
        return {
            "model": cfg.model,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "temperature": cfg.temperature,
            "max_tokens": cfg.max_tokens,
            "top_p": cfg.top_p,
            **(cfg.extra),
        }

    async def chat(self, messages: list[LLMMessage], config: LLMConfig | None = None) -> LLMResponse:
        payload = self._build_payload(messages, config)
        resp = await self._client.post(
            f"{self.base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
        resp.raise_for_status()
        data = resp.json()
        choice = data["choices"][0]
        return LLMResponse(
            content=choice["message"]["content"],
            model=data.get("model", ""),
            usage=data.get("usage"),
        )

    async def chat_stream(self, messages: list[LLMMessage], config: LLMConfig | None = None) -> AsyncIterator[str]:
        payload = self._build_payload(messages, config)
        payload["stream"] = True
        async with self._client.stream(
            "POST",
            f"{self.base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        ) as resp:
            resp.raise_for_status()
            async for line in resp.aiter_lines():
                if line.startswith("data: ") and line != "data: [DONE]":
                    import json
                    chunk = json.loads(line[6:])
                    delta = chunk.get("choices", [{}])[0].get("delta", {})
                    if "content" in delta:
                        yield delta["content"]

    async def close(self):
        await self._client.aclose()
