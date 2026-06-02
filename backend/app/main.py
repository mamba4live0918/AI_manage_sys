from contextlib import asynccontextmanager
import time
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.api import auth, files, preview, permissions, audit, copywriting, dashboard, department, marketing, bidding, pm, hr, finance, search
from app.database import engine
from app.models.models import Base


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    title=settings.PROJECT_NAME,
    version="0.1.0",
    lifespan=lifespan,
)

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    auth = request.headers.get("authorization", "none")[:30]
    origin = request.headers.get("origin", "no-origin")
    print(f"[REQ] {request.method} {request.url.path} | {response.status_code} | {duration:.3f}s | origin={origin} | auth={auth}")
    return response

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix=settings.API_PREFIX)
app.include_router(files.router, prefix=settings.API_PREFIX)
app.include_router(preview.router, prefix=settings.API_PREFIX)
app.include_router(permissions.router, prefix=settings.API_PREFIX)
app.include_router(audit.router, prefix=settings.API_PREFIX)
app.include_router(copywriting.router, prefix=settings.API_PREFIX)
app.include_router(dashboard.router, prefix=settings.API_PREFIX)
app.include_router(department.router, prefix=settings.API_PREFIX)
app.include_router(marketing.router, prefix=settings.API_PREFIX)
app.include_router(bidding.router, prefix=settings.API_PREFIX)
app.include_router(pm.router, prefix=settings.API_PREFIX)
app.include_router(hr.router, prefix=settings.API_PREFIX)
app.include_router(finance.router, prefix=settings.API_PREFIX)
app.include_router(search.router, prefix=settings.API_PREFIX)


@app.get("/health")
async def health():
    return {"status": "ok"}
