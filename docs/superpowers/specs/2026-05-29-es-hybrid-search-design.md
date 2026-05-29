# ES Hybrid Search — 设计文档

**日期**: 2026-05-29
**状态**: 待实现

## 目标

当前 ES 全文检索仅支持 BM25（`multi_match` + `cjk_ngram`），无法处理语义模糊查询（如"擅长数据库的候选人"、"项目遇到的技术难题"）。增加向量相似度搜索，与全文检索混合排序。

## 方案

ES hybrid search：BM25 全文 + knn 向量 → RRF (Reciprocal Rank Fusion) 融合排序。

## 技术选型

| 决策 | 选择 | 理由 |
|------|------|------|
| Embedding 模型 | DeepSeek embedding API | 与现有 LLM 共用 API key，零部署成本 |
| 向量生成时机 | `index_document()` 内部同步调用 | 调用方无感知，不改业务代码 |
| 融合方式 | RRF (Reciprocal Rank Fusion) | ES 8.x 原生支持，无需手动调权重 |
| 索引升级 | 删除重建 | 开发阶段数据量小 |
| Embedding 缓存 | 暂不做 | 当前数据量小，按需补 |

## 改动清单

### 1. `config.py` — 新增配置

```
EMBEDDING_MODEL: str = "deepseek-embedding"
EMBEDDING_DIM: int = 768
```

### 2. `services/embedding.py` — 新文件

- `async def get_embedding(text: str) -> list[float]`
- 调用 `{LLM_BASE_URL}/embeddings`，model=`EMBEDDING_MODEL`
- 复用 httpx.AsyncClient，走 settings 的 LLM_API_KEY
- 失败返回空列表，调用方降级为纯 BM25
- 函数内对 text 做截断（最长 8192 tokens ≈ 中文字符，实际按 API 限制调整）

### 3. `services/search.py` — ES 索引 + 写入 + 搜索

**索引 mapping 变更** (`_ensure_index`):
- 新增 `embedding` 字段：`dense_vector`，dims=768，index=true，similarity=cosine

**写入变更** (`index_document`):
- 新增 `embedding_text` 参数（默认用 `title + " " + content` 拼接）
- 写入前调 `get_embedding(embedding_text)` 生成向量
- 向量为空时仍写入文档（无 embedding 字段），纯 BM25 降级
- body 新增 `"embedding": vector`

**搜索变更** (`search`):
- 查询时先调 `get_embedding(query)` 生成查询向量
- body 新增 `knn` 子句：`{"field": "embedding", "query_vector": vec, "k": 100, "num_candidates": 200}`
- body 新增 `rank: {"rrf": {}}` 用于 RRF 融合
- 查询向量生成失败时，退化为纯 BM25（当前逻辑）

### 4. 调用方 — 不变

bidding/hr/pm/marketing 的 `es_index()` 调用无需任何改动。`index_document()` 接口兼容，内部自动处理 embedding。

## 搜索流程

```
用户查询 "擅长数据库的候选人"
  → get_embedding("擅长数据库的候选人")
  → ES query { knn: { embedding }, query: { multi_match }, rank: { rrf } }
  → 返回 RRF 融合排序结果
  → embedding 失败? → 降级纯 BM25
```

## 降级策略

| 场景 | 行为 |
|------|------|
| embedding API 不可用 | 写入跳过向量，搜索退化为纯 BM25 |
| ES 不可用 | 搜索返回空（现有行为不变） |
| 旧文档无向量 | knn 只命中新文档，BM25 覆盖全部，RRF 自然融合 |
