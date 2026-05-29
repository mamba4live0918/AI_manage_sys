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
