from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # ── 应用 ──
    PROJECT_NAME: str = "AI_manage_sys"
    API_PREFIX: str = "/api"
    CORS_ORIGINS: list[str] = ["*"]
    DEBUG: bool = True

    # ── 数据库 ──
    DATABASE_URL: str = "postgresql+asyncpg://ai_manage:ai_manage_dev@localhost:5433/ai_manage"

    # ── Redis ──
    REDIS_URL: str = "redis://localhost:6379/0"

    # ── JWT ──
    JWT_SECRET: str = "change-me-in-production-use-rand-64-chars"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 480  # 8小时

    # ── MinIO ──
    MINIO_ENDPOINT: str = "localhost:9000"
    MINIO_ACCESS_KEY: str = "minioadmin"
    MINIO_SECRET_KEY: str = "minioadmin"
    MINIO_BUCKET: str = "ai-manage-files"
    MINIO_SECURE: bool = False

    # ── LLM ──
    LLM_PROVIDER: str = "openai_compatible"
    LLM_BASE_URL: str = "https://api.deepseek.com/v1"    # 开发阶段用免费/便宜API
    LLM_API_KEY: str = ""                                  # 填你的key
    LLM_MODEL: str = "deepseek-chat"
    LLM_TIMEOUT: float = 60.0

    # 切换本地模型示例（改环境变量即可）:
    # LLM_BASE_URL=http://localhost:8000/v1   # vLLM/Ollama
    # LLM_API_KEY=not-needed
    # LLM_MODEL=qwen2.5-14b

    class Config:
        env_file = ".env"
        extra = "allow"


settings = Settings()
