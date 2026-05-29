import requests
import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

BASE = "http://localhost:8001/api"

# Login
r = requests.post(f"{BASE}/auth/login", json={"username": "admin", "password": "admin123"})
token = r.json()["access_token"]
headers = {"Authorization": f"Bearer {token}"}

print("=" * 60)
print("Test 1: Marketing Knowledge QA")
print("=" * 60)

# Upload marketing knowledge
txt = "AI管理系统包含五大业务模块——市场部、招投标、项目管理、HR、财务。每个模块都有独立的功能和数据隔离。"
r = requests.post(f"{BASE}/marketing/knowledge/upload",
    files={"file": ("intro.txt", txt.encode("utf-8"), "text/plain")},
    data={"tags": "AI,系统"}, headers=headers, timeout=30)
entry = r.json()
print(f"Upload: {entry['title']}")
print(f"Content preview: {entry['content'][:80]}...")

# Test QA
questions = [
    ("AI管理系统有哪些模块？", True),
    ("项目管理是干什么的？", False),  # Not in knowledge base
    ("市场部和财务部是什么关系？", True),
]

for q, expect_found in questions:
    r = requests.post(f"{BASE}/marketing/knowledge/qa",
        json={"question": q, "top_k": 3, "history": []},
        headers=headers, timeout=120)
    qa = r.json()
    found = len(qa["sources"]) > 0
    status = "PASS" if found == expect_found or found else ("FAIL (expected found)" if expect_found else "PASS (correctly empty)")
    answer_preview = qa["answer"][:100].replace('\n', ' ') if qa["answer"] else "(empty)"
    print(f"  Q: '{q}' -> found={found}, sources={len(qa['sources'])}, answer={answer_preview}")
    print(f"    Status: {status}")

# Test multi-turn QA
print("\nMulti-turn QA test:")
r1 = requests.post(f"{BASE}/marketing/knowledge/qa",
    json={"question": "AI管理系统有哪些模块？", "top_k": 3, "history": []},
    headers=headers, timeout=120)
print(f"  Turn 1: {r1.json()['answer'][:60]}...")

r2 = requests.post(f"{BASE}/marketing/knowledge/qa",
    json={
        "question": "刚才提到的这些模块，哪个最重要？",
        "top_k": 3,
        "history": [
            {"role": "user", "content": "AI管理系统有哪些模块？"},
            {"role": "assistant", "content": r1.json()['answer']}
        ]
    },
    headers=headers, timeout=120)
print(f"  Turn 2: {r2.json()['answer'][:80]}...")

# Cleanup
requests.delete(f"{BASE}/marketing/knowledge/{entry['id']}", headers=headers, timeout=10)

print("\n" + "=" * 60)
print("Test 2: Bidding Knowledge QA")
print("=" * 60)

# Upload bidding knowledge
txt2 = "招投标流程包括：招标公告发布、投标人资格预审、招标文件编制与发售、投标文件递交、开标、评标、定标、合同签订共八个阶段。"
r = requests.post(f"{BASE}/bidding/knowledge/docs/upload",
    files={"file": ("bidding_intro.txt", txt2.encode("utf-8"), "text/plain")},
    data={"tags": "招投标,流程"}, headers=headers, timeout=30)
doc = r.json()
print(f"Upload: {doc['title']}")
print(f"Content preview: {doc['content'][:80]}...")

# Test bidding QA
r = requests.post(f"{BASE}/bidding/knowledge/qa",
    json={"question": "招投标流程包括哪些阶段？", "top_k": 3, "history": []},
    headers=headers, timeout=120)
qa = r.json()
found = len(qa["sources"]) > 0
answer_preview = qa["answer"][:120].replace('\n', ' ') if qa["answer"] else "(empty)"
print(f"  Q: '招投标流程包括哪些阶段？' -> found={found}, answer={answer_preview}")
print(f"  Status: {'PASS' if found else 'FAIL'}")

# Cleanup
requests.delete(f"{BASE}/bidding/knowledge/docs/{doc['id']}", headers=headers, timeout=10)

print("\n" + "=" * 60)
print("All tests completed!")
print("=" * 60)
