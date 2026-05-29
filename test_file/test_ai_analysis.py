import requests
import json
import sys

BASE = "http://localhost:8001/api"

# Login
resp = requests.post(f"{BASE}/auth/login", json={"username": "admin", "password": "admin123"})
token = resp.json()["access_token"]

def upload(filename, name):
    with open(filename, "rb") as f:
        resp = requests.post(f"{BASE}/hr/resumes/upload",
            files={"file": (filename, f, "text/plain")},
            data={"name": name},
            headers={"Authorization": f"Bearer {token}"})
    return resp.json()["id"]

def analyze(resume_id, label):
    print(f"\n{'='*60}")
    print(f"=== {label} ===")
    print(f"{'='*60}")
    resp = requests.post(f"{BASE}/hr/resumes/{resume_id}/match",
                         headers={"Authorization": f"Bearer {token}"})
    data = resp.json()
    match_score = data.get("match_score")
    print(f"Match Score: {match_score}")
    analysis = data.get("analysis", {})
    if not analysis:
        print("No analysis returned!")
        print(f"Response keys: {data.keys()}")
        return

    overall = analysis.get("overall_score")
    print(f"Overall Score: {overall}")
    print(f"\n--- Dimension Scores ---")
    scores = analysis.get("scores", {})
    for dim, val in scores.items():
        if isinstance(val, dict):
            print(f"  {dim}: {val.get('score')} — {val.get('evidence', '')}")
        else:
            print(f"  {dim}: {val}")
    print(f"\n--- Strengths ---")
    print(analysis.get("strengths", "(none)"))
    print(f"\n--- Weaknesses ---")
    print(analysis.get("weaknesses", "(none)"))
    print(f"\n--- Department Matches ---")
    for dm in analysis.get("department_matches", []):
        print(f"  {dm.get('department', '?')}: {dm.get('score', '?')}% — {dm.get('reason', '')}")
    print(f"\n--- Salary ---")
    print(analysis.get("recommended_salary", "(none)"))
    print(f"\n--- Summary ---")
    print(analysis.get("summary", "(none)"))

# Upload and analyze
sid = upload("resume_senior.txt", "张伟")
jid = upload("resume_junior.txt", "李明")

analyze(sid, "Senior: 张伟 (10年经验/清华/字节)")
analyze(jid, "Junior: 李明 (1.5年经验/普通本科/CRUD)")
