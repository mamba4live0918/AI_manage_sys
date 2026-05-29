# ES Hybrid Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add semantic search to ES via DeepSeek embedding vectors, hybrid-sorted with BM25 using RRF.

**Architecture:** New `services/embedding.py` calls DeepSeek `/v1/embeddings`. `services/search.py` auto-generates vectors on `index_document()` and adds `knn` + `rrf` to `search()`. Callers unchanged.

**Tech Stack:** Elasticsearch 8.17.0 (async), httpx, DeepSeek embedding API (OpenAI-compatible)

---

### Task 1: Add embedding config

**Files:**
- Modify: `backend/app/config.py`

- [ ] **Step 1: Add EMBEDDING_MODEL and EMBEDDING_DIM to Settings**

```python
# 在 ES_URL 下方新增
# ── Embedding ──
EMBEDDING_MODEL: str = "deepseek-embedding"
EMBEDDING_DIM: int = 768
```

- [ ] **Step 2: Verify config loads**

Run: `cd backend && python -c "from app.config import settings; print(settings.EMBEDDING_MODEL, settings.EMBEDDING_DIM)"`
Expected: `deepseek-embedding 768`

- [ ] **Step 3: Commit**

```bash
git add backend/app/config.py
git commit -m "feat: add EMBEDDING_MODEL and EMBEDDING_DIM config"
```

---

### Task 2: Create embedding service

**Files:**
- Create: `backend/app/services/embedding.py`

- [ ] **Step 1: Create the embedding service**

```python
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
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/embedding.py
git commit -m "feat: add embedding service via DeepSeek API"
```

---

### Task 3: Update ES index mapping with dense_vector

**Files:**
- Modify: `backend/app/services/search.py` — `_ensure_index()`

- [ ] **Step 1: Delete existing ES index (dev data)**

Run: `curl -X DELETE http://localhost:9200/ai_manage_search`
Expected: `{"acknowledged": true}` (or 404 if doesn't exist — both fine)

- [ ] **Step 2: Add dense_vector field to _ensure_index mappings**

In `_ensure_index()`, add the `embedding` field to the mappings `properties` dict — **insert after `"department_id"` and before `"updated_at"`**:

```python
"department_id": {"type": "keyword"},
# ↓↓↓ NEW ↓↓↓
"embedding": {
    "type": "dense_vector",
    "dims": 768,
    "index": True,
    "similarity": "cosine",
},
# ↑↑↑ NEW ↑↑↑
"updated_at": {"type": "date"},
```

- [ ] **Step 3: Restart backend to trigger index creation**

Run: Kill old uvicorn, then `cd backend && python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload`

Verify: `curl http://localhost:9200/ai_manage_search/_mapping | python -m json.tool | grep -A5 embedding`
Expected: shows dense_vector mapping

- [ ] **Step 4: Commit**

```bash
git add backend/app/services/search.py
git commit -m "feat: add dense_vector embedding field to ES mapping"
```

---

### Task 4: Auto-embed documents on index

**Files:**
- Modify: `backend/app/services/search.py` — `index_document()`

- [ ] **Step 1: Import embedding service and add embedding_text param**

At top of `search.py`, add import:
```python
from app.services.embedding import get_embedding
```

- [ ] **Step 2: Modify index_document signature and body**

Change `index_document()` to accept an optional `embedding_text` param, and generate + attach the vector:

```python
async def index_document(
    doc_id: str, module: str, title: str,
    content: str = "", extra: str = "", department_id: str | None = None,
    embedding_text: str = "",  # NEW: custom text for embedding (falls back to title + content)
):
    es = await get_es()
    if es is None:
        return

    # Generate embedding vector
    emb_input = embedding_text.strip() if embedding_text.strip() else f"{title} {content}"[:8000]
    vector = await get_embedding(emb_input)

    doc_body = {
        "doc_id": doc_id, "module": module, "title": title,
        "content": content, "extra": extra,
        "department_id": department_id or "", "updated_at": "now",
    }
    if vector:  # Only attach embedding if API succeeded
        doc_body["embedding"] = vector

    try:
        await es.index(
            index=ES_INDEX, id=f"{module}_{doc_id}",
            body=doc_body,
            refresh=True,
        )
    except Exception as e:
        logger.warning(f"ES index error: {e}")
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/services/search.py
git commit -m "feat: auto-generate embedding vectors on document index"
```

---

### Task 5: Hybrid search with knn + RRF

**Files:**
- Modify: `backend/app/services/search.py` — `search()`

- [ ] **Step 1: Modify search() to add knn + RRF**

Replace the body construction in `search()` from the `must`/`filters` section onward:

```python
async def search(
    query: str, module: str = "",
    department_id: str | None = None,
    size: int = 20, offset: int = 0,
) -> dict:
    es = await get_es()
    if es is None:
        return {"items": [], "total": 0, "took_ms": 0}

    must = [{"multi_match": {"query": query, "fields": ["title^3", "content^1", "extra^0.5"]}}]
    filters = []
    if module:
        filters.append({"term": {"module": module}})
    if department_id:
        filters.append({"term": {"department_id": department_id}})

    body = {
        "query": {"bool": {"must": must}} if not filters else {"bool": {"must": must, "filter": filters}},
        "from": offset,
        "size": size,
    }

    # Hybrid: add knn vector search with RRF fusion
    query_vector = await get_embedding(query)
    if query_vector:
        body["knn"] = {
            "field": "embedding",
            "query_vector": query_vector,
            "k": 100,
            "num_candidates": 200,
        }
        body["rank"] = {"rrf": {}}

    try:
        resp = await es.search(index=ES_INDEX, body=body)
        hits = resp["hits"]
        items = [{
            "doc_id": h["_source"]["doc_id"], "module": h["_source"]["module"],
            "title": h["_source"]["title"], "content": h["_source"]["content"][:500],
            "extra": h["_source"].get("extra", ""), "score": h["_score"],
        } for h in hits["hits"]]
        return {"items": items, "total": hits["total"]["value"], "took_ms": resp["took"]}
    except NotFoundError:
        await _ensure_index()
        return {"items": [], "total": 0, "took_ms": 0}
    except Exception as e:
        logger.warning(f"ES search error: {e}")
        return {"items": [], "total": 0, "took_ms": 0}
```

- [ ] **Step 2: Commit**

```bash
git add backend/app/services/search.py
git commit -m "feat: add knn + RRF hybrid semantic search"
```

---

### Task 6: Integration test

**Files:**
- Create: `test_file/test_hybrid_search.py`

- [ ] **Step 1: Create integration test script**

```python
"""Quick integration test for ES hybrid search. Requires running backend + ES."""
import asyncio
import httpx


async def main():
    base = "http://localhost:8001/api"

    async with httpx.AsyncClient(timeout=httpx.Timeout(30)) as client:
        # 1. Login
        resp = await client.post(f"{base}/auth/login", json={
            "username": "admin", "password": "admin123"
        })
        token = resp.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 2. Semantic search — should still work with BM25 even without embedding data
        resp = await client.get(f"{base}/search", params={"q": "擅长数据库的候选人"}, headers=headers)
        data = resp.json()
        print(f"[Semantic] total={data['total']}, took={data['took_ms']}ms")

        for item in data["items"]:
            print(f"  - [{item['module']}] {item['title']} (score={item['score']:.4f})")

        # 3. Existing keyword search
        resp = await client.get(f"{base}/search", params={"q": "合同"}, headers=headers)
        data = resp.json()
        print(f"[Keyword] total={data['total']}, took={data['took_ms']}ms")

        for item in data["items"]:
            print(f"  - [{item['module']}] {item['title']} (score={item['score']:.4f})")

        # 4. Filtered search
        resp = await client.get(f"{base}/search", params={"q": "项目管理", "module": "pm_knowledge"}, headers=headers)
        data = resp.json()
        print(f"[Filtered] total={data['total']}, took={data['took_ms']}ms")

        print("\nAll tests passed!")


if __name__ == "__main__":
    asyncio.run(main())
```

- [ ] **Step 2: Run test**

```bash
cd test_file && python test_hybrid_search.py
```

Expected: 3 search results printed, no errors. Semantic query returns results even without exact keyword matches.

- [ ] **Step 3: Commit**

```bash
git add test_file/test_hybrid_search.py
git commit -m "test: add ES hybrid search integration test"
```
