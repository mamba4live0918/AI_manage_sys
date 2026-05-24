from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import AsyncIterator


@dataclass
class LLMMessage:
    role: str  # "system" | "user" | "assistant"
    content: str


@dataclass
class LLMResponse:
    content: str
    model: str = ""
    usage: dict | None = None  # {"prompt_tokens": N, "completion_tokens": N}


@dataclass
class LLMConfig:
    model: str = "deepseek-chat"
    temperature: float = 0.7
    max_tokens: int = 4096
    top_p: float = 1.0
    extra: dict = field(default_factory=dict)


class BaseLLMProvider(ABC):
    """统一LLM抽象 —— 所有后端实现同一接口，配置驱动切换"""

    @abstractmethod
    async def chat(
        self,
        messages: list[LLMMessage],
        config: LLMConfig | None = None,
    ) -> LLMResponse:
        """单轮对话，返回完整响应"""
        ...

    @abstractmethod
    async def chat_stream(
        self,
        messages: list[LLMMessage],
        config: LLMConfig | None = None,
    ) -> AsyncIterator[str]:
        """流式对话，逐token返回"""
        ...

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        config: LLMConfig | None = None,
    ) -> LLMResponse:
        """便捷方法：system + user → response"""
        return await self.chat(
            [
                LLMMessage(role="system", content=system_prompt),
                LLMMessage(role="user", content=user_prompt),
            ],
            config,
        )
