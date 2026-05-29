"""Elasticsearch full-text search service. Fails gracefully if ES is unavailable."""
import logging
from elasticsearch import AsyncElasticsearch, NotFoundError, ConnectionError as ESConnectionError
from app.config import settings
from app.services.embedding import get_embedding

logger = logging.getLogger(__name__)

ES_INDEX = "ai_manage_search"
_es: AsyncElasticsearch | None = None
_available: bool = True


async def get_es() -> AsyncElasticsearch | None:
    global _es, _available
    if not _available:
        return None
    if _es is None:
        try:
            _es = AsyncElasticsearch(settings.ES_URL, request_timeout=5)
            await _ensure_index()
        except ESConnectionError:
            _available = False
            _es = None
            logger.warning("Elasticsearch unavailable — search disabled")
            return None
    return _es


async def _ensure_index():
    global _es, _available
    try:
        exists = await _es.indices.exists(index=ES_INDEX)
        if not exists:
            await _es.indices.create(
                index=ES_INDEX,
                body={
                    "settings": {
                        "analysis": {
                            "analyzer": {
                                "cjk_ngram": {
                                    "type": "custom",
                                    "tokenizer": "standard",
                                    "filter": ["lowercase", "cjk_width"],
                                }
                            }
                        }
                    },
                    "mappings": {
                        "properties": {
                            "doc_id": {"type": "keyword"},
                            "module": {"type": "keyword"},
                            "title": {"type": "text", "analyzer": "cjk_ngram"},
                            "content": {"type": "text", "analyzer": "cjk_ngram"},
                            "extra": {"type": "text"},
                            "department_id": {"type": "keyword"},
                            "embedding": {
                                "type": "dense_vector",
                                "dims": 768,
                                "index": True,
                                "similarity": "cosine",
                            },
                            "updated_at": {"type": "date"},
                        }
                    },
                },
            )
            logger.info(f"Created ES index: {ES_INDEX}")
    except ESConnectionError:
        _available = False
        _es = None


async def index_document(
    doc_id: str, module: str, title: str,
    content: str = "", extra: str = "", department_id: str | None = None,
    embedding_text: str = "",
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
    if vector:
        doc_body["embedding"] = vector

    try:
        await es.index(
            index=ES_INDEX, id=f"{module}_{doc_id}",
            body=doc_body,
            refresh=True,
        )
    except Exception as e:
        logger.warning(f"ES index error: {e}")


async def delete_document(doc_id: str, module: str):
    es = await get_es()
    if es is None:
        return
    try:
        await es.delete(index=ES_INDEX, id=f"{module}_{doc_id}", refresh=True)
    except (NotFoundError, Exception):
        pass


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

    body = {"query": {"bool": {"must": must}}} if not filters else {"query": {"bool": {"must": must, "filter": filters}}}
    body["from"] = offset
    body["size"] = size

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
