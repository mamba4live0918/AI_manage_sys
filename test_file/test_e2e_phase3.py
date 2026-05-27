"""Phase 3 E2E Tests — Marketing + Bidding full API coverage"""
import requests
import json
import sys
import os
import time

BASE = "http://localhost:8001/api"
PASSED = 0
FAILED = 0
CREATED = {}  # track created resources for cleanup

def login(username="admin", password="admin123"):
    r = requests.post(f"{BASE}/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, f"Login failed: {r.status_code}"
    return r.json()["access_token"]

def test(name, fn):
    global PASSED, FAILED
    try:
        fn()
        PASSED += 1
        print(f"  [PASS] {name}")
    except Exception as e:
        FAILED += 1
        print(f"  [FAIL] {name} — {e}")

def main():
    global PASSED, FAILED
    token = login()
    h = {"Authorization": f"Bearer {token}"}

    # ═══════════════════════════════════════════
    # MARKETING
    # ═══════════════════════════════════════════

    # ── Customers ──
    print("\n===== Marketing: Customers =====")
    customer_id = None

    def create_customer():
        nonlocal customer_id
        r = requests.post(f"{BASE}/marketing/customers", json={
            "name": "E2E测试客户",
            "industry": "信息技术",
            "contact_name": "张三",
            "contact_phone": "13800138000",
            "contact_email": "zhangsan@test.com",
            "source": "线上推广",
            "status": "active",
            "tags": ["测试", "VIP"],
            "notes": "自动化测试创建"
        }, headers=h)
        assert r.status_code == 200, f"Create customer failed: {r.text}"
        customer_id = r.json()["id"]
        CREATED["customer"] = customer_id

    test("POST /customers — 创建客户", create_customer)

    def list_customers():
        r = requests.get(f"{BASE}/marketing/customers", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        items = r.json()["items"]
        assert len(items) > 0, "No customers found"

    test("GET /customers — 客户列表", list_customers)

    def get_customer():
        r = requests.get(f"{BASE}/marketing/customers/{customer_id}", headers=h)
        assert r.status_code == 200
        assert r.json()["name"] == "E2E测试客户"

    test("GET /customers/{id} — 客户详情", get_customer)

    def update_customer():
        r = requests.put(f"{BASE}/marketing/customers/{customer_id}", json={
            "name": "E2E测试客户(已更新)",
            "industry": "金融科技",
            "status": "active"
        }, headers=h)
        assert r.status_code == 200
        assert r.json()["name"] == "E2E测试客户(已更新)"

    test("PUT /customers/{id} — 更新客户", update_customer)

    # ── Behaviors ──
    print("\n===== Marketing: Customer Behaviors =====")
    behavior_id = None

    def create_behavior():
        nonlocal behavior_id
        r = requests.post(f"{BASE}/marketing/customers/{customer_id}/behaviors", json={
            "event_type": "meeting",
            "description": "需求沟通会议",
            "event_date": "2026-05-27"
        }, headers=h)
        assert r.status_code == 200
        behavior_id = r.json()["id"]

    test("POST /customers/{id}/behaviors — 添加行为", create_behavior)

    def list_behaviors():
        r = requests.get(f"{BASE}/marketing/customers/{customer_id}/behaviors", headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /customers/{id}/behaviors — 行为列表", list_behaviors)

    # ── Satisfactions ──
    print("\n===== Marketing: Customer Satisfaction =====")

    def create_satisfaction():
        r = requests.post(f"{BASE}/marketing/customers/{customer_id}/satisfactions", json={
            "score": 85,
            "comment": "服务态度很好",
            "survey_date": "2026-05-27"
        }, headers=h)
        assert r.status_code == 200

    test("POST /customers/{id}/satisfactions — 添加满意度", create_satisfaction)

    def list_satisfactions():
        r = requests.get(f"{BASE}/marketing/customers/{customer_id}/satisfactions", headers=h)
        assert r.status_code == 200

    test("GET /customers/{id}/satisfactions — 满意度列表", list_satisfactions)

    def satisfaction_trend():
        r = requests.get(f"{BASE}/marketing/customers/{customer_id}/satisfaction-trend", headers=h)
        assert r.status_code == 200
        assert "trend" in r.json()

    test("GET /customers/{id}/satisfaction-trend — 满意度趋势", satisfaction_trend)

    # ── Churn Config ──
    print("\n===== Marketing: Churn Config =====")

    def get_churn_config():
        r = requests.get(f"{BASE}/marketing/churn-config", headers=h)
        assert r.status_code == 200

    test("GET /churn-config — 流失配置", get_churn_config)

    def update_churn_config():
        r = requests.put(f"{BASE}/marketing/churn-config", json={
            "inactive_days_threshold": 90,
            "low_satisfaction_threshold": 60,
            "auto_notify": True
        }, headers=h)
        assert r.status_code == 200

    test("PUT /churn-config — 更新流失配置", update_churn_config)

    def check_churn():
        r = requests.post(f"{BASE}/marketing/customers/{customer_id}/check-churn", headers=h, timeout=60)
        assert r.status_code == 200

    test("POST /customers/{id}/check-churn — 流失检查", check_churn)

    def list_warnings():
        r = requests.get(f"{BASE}/marketing/churn-warnings", headers=h)
        assert r.status_code == 200

    test("GET /churn-warnings — 预警列表", list_warnings)

    # ── Proposals ──
    print("\n===== Marketing: Proposals =====")
    proposal_id = None

    def generate_proposal():
        nonlocal proposal_id
        r = requests.post(f"{BASE}/marketing/proposals/generate", json={
            "title": "智能客服系统升级方案",
            "customer_id": customer_id,
            "topic": "智能客服系统升级",
            "requirements": "提升客服效率30%，支持多渠道接入",
            "additional_info": "预算50万元，周期6个月"
        }, headers=h, timeout=120)
        assert r.status_code == 200, f"Generate proposal failed: {r.text}"
        proposal_id = r.json()["id"]
        CREATED["proposal"] = proposal_id

    test("POST /proposals/generate — LLM方案生成", generate_proposal)

    def list_proposals():
        r = requests.get(f"{BASE}/marketing/proposals", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /proposals — 方案列表", list_proposals)

    def get_proposal():
        r = requests.get(f"{BASE}/marketing/proposals/{proposal_id}", headers=h)
        assert r.status_code == 200

    test("GET /proposals/{id} — 方案详情", get_proposal)

    # ── Projects ──
    print("\n===== Marketing: Projects =====")
    project_id = None

    def create_project():
        nonlocal project_id
        r = requests.post(f"{BASE}/marketing/projects", json={
            "customer_id": customer_id,
            "name": "E2E测试项目",
            "stage": "planning",
            "data_source": {"platform": "internal", "ref": "test-001"}
        }, headers=h)
        assert r.status_code == 200
        project_id = r.json()["id"]
        CREATED["project"] = project_id

    test("POST /projects — 创建项目", create_project)

    def list_projects():
        r = requests.get(f"{BASE}/marketing/projects", headers=h)
        assert r.status_code == 200

    test("GET /projects — 项目列表", list_projects)

    def project_timeline():
        r = requests.get(f"{BASE}/marketing/projects/{project_id}/timeline", headers=h)
        assert r.status_code == 200

    test("GET /projects/{id}/timeline — 项目时间轴", project_timeline)

    def project_brief():
        r = requests.post(f"{BASE}/marketing/projects/{project_id}/brief", headers=h, timeout=120)
        assert r.status_code == 200

    test("POST /projects/{id}/brief — LLM项目简报", project_brief)

    # ── Community ──
    print("\n===== Marketing: Community =====")
    interaction_id = None

    def create_interaction():
        nonlocal interaction_id
        r = requests.post(f"{BASE}/marketing/community/interactions", json={
            "platform": "wechat",
            "group_name": "客户服务交流群",
            "username": "测试用户A",
            "content": "你们的服务真不错，响应很快！",
            "tags": ["表扬", "服务"]
        }, headers=h)
        assert r.status_code == 200
        interaction_id = r.json()["id"]

    test("POST /community/interactions — 创建互动", create_interaction)

    def list_interactions():
        r = requests.get(f"{BASE}/marketing/community/interactions", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /community/interactions — 互动列表", list_interactions)

    def community_activity():
        r = requests.get(f"{BASE}/marketing/community/activity", headers=h)
        assert r.status_code == 200

    test("GET /community/activity — 社群活跃度", community_activity)

    def hot_topics():
        r = requests.get(f"{BASE}/marketing/community/hot-topics", headers=h)
        assert r.status_code == 200

    test("GET /community/hot-topics — 热词提取", hot_topics)

    # ── Knowledge ──
    print("\n===== Marketing: Knowledge Base =====")
    entry_id = None

    def upload_knowledge():
        nonlocal entry_id
        txt = "市场部E2E测试文档：客户满意度达到95%以上，年度营收增长30%。"
        r = requests.post(f"{BASE}/marketing/knowledge/upload",
            files={"file": ("e2e_marketing.txt", txt.encode("utf-8"), "text/plain")},
            data={"tags": "e2e,市场部"}, headers=h, timeout=30)
        assert r.status_code == 200, f"Upload failed: {r.text}"
        entry_id = r.json()["id"]
        CREATED["knowledge_entry"] = entry_id

    test("POST /knowledge/upload — 知识上传", upload_knowledge)

    def knowledge_list():
        r = requests.get(f"{BASE}/marketing/knowledge", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /knowledge — 知识列表", knowledge_list)

    def knowledge_qa():
        r = requests.post(f"{BASE}/marketing/knowledge/qa", json={
            "question": "客户满意度是多少？",
            "top_k": 3,
            "history": []
        }, headers=h, timeout=120)
        assert r.status_code == 200
        assert len(r.json()["sources"]) > 0, "QA found no sources"

    test("POST /knowledge/qa — 知识问答（有来源）", knowledge_qa)

    def knowledge_multi_turn_qa():
        r1 = requests.post(f"{BASE}/marketing/knowledge/qa", json={
            "question": "市场部的营收增长多少？",
            "top_k": 3, "history": []
        }, headers=h, timeout=120)
        assert r1.status_code == 200, f"QA1 failed: {r1.text}"
        r2 = requests.post(f"{BASE}/marketing/knowledge/qa", json={
            "question": "刚才提到的数据，还能说得更具体吗？",
            "top_k": 3,
            "history": [
                {"role": "user", "content": "市场部的营收增长多少？"},
                {"role": "assistant", "content": r1.json()["answer"]}
            ]
        }, headers=h, timeout=120)
        assert r2.status_code == 200, f"Multi-turn QA failed: {r2.text}"

    test("POST /knowledge/qa — 多轮对话", knowledge_multi_turn_qa)

    def qa_history():
        r = requests.get(f"{BASE}/marketing/knowledge/qa-history", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /knowledge/qa-history — QA历史", qa_history)

    def demand_prediction():
        r = requests.post(f"{BASE}/marketing/customers/{customer_id}/predict-demand",
            headers=h, timeout=120)
        assert r.status_code == 200

    test("POST /customers/{id}/predict-demand — LLM需求预测", demand_prediction)

    # ═══════════════════════════════════════════
    # BIDDING
    # ═══════════════════════════════════════════

    # ── Contract Templates ──
    print("\n===== Bidding: Contract Templates =====")
    template_id = None

    def create_template():
        nonlocal template_id
        r = requests.post(f"{BASE}/bidding/templates", json={
            "name": "E2E测试技术服务合同模板",
            "type": "技术服务合同",
            "content": "甲方：{{client_name}}\n乙方：{{company_name}}\n合同金额：{{amount}}\n服务期限：{{period}}",
            "system_prompt": "你是一个专业的合同撰写助手，请根据模板变量填写合同。"
        }, headers=h)
        assert r.status_code == 200
        template_id = r.json()["id"]
        CREATED["template"] = template_id

    test("POST /templates — 创建合同模板", create_template)

    def list_templates():
        r = requests.get(f"{BASE}/bidding/templates", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /templates — 模板列表", list_templates)

    # ── Contracts ──
    print("\n===== Bidding: Contracts =====")
    contract_id = None

    def create_contract():
        nonlocal contract_id
        r = requests.post(f"{BASE}/bidding/contracts", json={
            "template_id": template_id,
            "title": "E2E智能客服系统合同",
            "counterparty": "测试科技有限公司",
            "variables": {
                "client_name": "测试科技",
                "company_name": "AI管理系统公司",
                "amount": "500,000",
                "period": "12个月"
            }
        }, headers=h, timeout=120)
        assert r.status_code == 200, f"Create contract failed: {r.text}"
        contract_id = r.json()["id"]
        CREATED["contract"] = contract_id

    test("POST /contracts — LLM生成合同", create_contract)

    def list_contracts():
        r = requests.get(f"{BASE}/bidding/contracts", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /contracts — 合同列表", list_contracts)

    def get_contract():
        r = requests.get(f"{BASE}/bidding/contracts/{contract_id}", headers=h)
        assert r.status_code == 200

    test("GET /contracts/{id} — 合同详情", get_contract)

    def update_contract():
        r = requests.put(f"{BASE}/bidding/contracts/{contract_id}", json={
            "title": "E2E智能客服系统合同(修订版)"
        }, headers=h)
        assert r.status_code == 200

    test("PUT /contracts/{id} — 更新合同", update_contract)

    def contract_versions():
        r = requests.get(f"{BASE}/bidding/contracts/{contract_id}/versions", headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /contracts/{id}/versions — 合同版本", contract_versions)

    def contract_diff():
        r = requests.get(f"{BASE}/bidding/contracts/{contract_id}/diff", params={"v1": 1, "v2": 1}, headers=h)
        assert r.status_code == 200

    test("GET /contracts/{id}/diff — 版本对比", contract_diff)

    # ── Knowledge Base ──
    print("\n===== Bidding: Knowledge Base =====")
    dir_id = None
    doc_id = None

    def create_dir():
        nonlocal dir_id
        r = requests.post(f"{BASE}/bidding/knowledge/dirs", json={
            "name": "E2E测试目录",
            "parent_id": None
        }, headers=h)
        assert r.status_code == 200
        dir_id = r.json()["id"]
        CREATED["knowledge_dir"] = dir_id

    test("POST /knowledge/dirs — 创建目录", create_dir)

    def list_dirs():
        r = requests.get(f"{BASE}/bidding/knowledge/dirs", headers=h)
        assert r.status_code == 200

    test("GET /knowledge/dirs — 目录列表", list_dirs)

    def upload_doc():
        nonlocal doc_id
        txt = "招投标E2E测试：供应商评估标准包括技术能力(30%)、报价合理性(35%)、项目经验(20%)、售后服务(15%)。"
        r = requests.post(f"{BASE}/bidding/knowledge/docs/upload",
            files={"file": ("e2e_bidding.txt", txt.encode("utf-8"), "text/plain")},
            data={"dir_id": dir_id, "tags": "e2e,评估标准"}, headers=h, timeout=30)
        assert r.status_code == 200, f"Upload doc failed: {r.text}"
        doc_id = r.json()["id"]
        CREATED["knowledge_doc"] = doc_id

    test("POST /knowledge/docs/upload — 文档上传", upload_doc)

    def list_docs():
        r = requests.get(f"{BASE}/bidding/knowledge/docs", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /knowledge/docs — 文档列表", list_docs)

    def search_docs():
        r = requests.get(f"{BASE}/bidding/knowledge/search", params={"q": "供应商评估", "limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0, "Search found no results"

    test("GET /knowledge/search — 全文搜索", search_docs)

    def recommend_docs():
        r = requests.post(f"{BASE}/bidding/knowledge/recommend", json={
            "query": "如何选择供应商？",
            "top_k": 3
        }, headers=h)
        assert r.status_code == 200

    test("POST /knowledge/recommend — 相似案例推荐", recommend_docs)

    def bidding_qa():
        r = requests.post(f"{BASE}/bidding/knowledge/qa", json={
            "question": "供应商评估的评分标准是什么？",
            "top_k": 3, "history": []
        }, headers=h, timeout=120)
        assert r.status_code == 200
        assert len(r.json()["sources"]) > 0, "Bidding QA found no sources"

    test("POST /knowledge/qa — 招投标签QA", bidding_qa)

    # ── Processes ──
    print("\n===== Bidding: Processes =====")
    process_id = None

    def create_process():
        nonlocal process_id
        r = requests.post(f"{BASE}/bidding/processes", json={
            "project_name": "E2E测试招投标项目",
            "stage": "bidding_prep",
            "deadline": "2026-07-01",
            "notes": "自动化测试"
        }, headers=h)
        assert r.status_code == 200
        process_id = r.json()["id"]
        CREATED["process"] = process_id

    test("POST /processes — 创建流程", create_process)

    def list_processes():
        r = requests.get(f"{BASE}/bidding/processes", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /processes — 流程列表", list_processes)

    def update_process():
        r = requests.put(f"{BASE}/bidding/processes/{process_id}", json={
            "stage": "opening"
        }, headers=h)
        assert r.status_code == 200

    test("PUT /processes/{id} — 更新流程阶段", update_process)

    # ── Suppliers ──
    print("\n===== Bidding: Suppliers =====")
    supplier_id = None

    def create_supplier():
        nonlocal supplier_id
        r = requests.post(f"{BASE}/bidding/suppliers", json={
            "name": "E2E测试供应商",
            "type": "技术服务",
            "contact_person": "李四",
            "contact_phone": "13900139000",
            "contact_email": "lisi@test.com",
            "tags": ["认证", "ISO9001"],
            "expertise": ["AI系统开发", "云服务"],
            "rating": 4.5
        }, headers=h)
        assert r.status_code == 200
        supplier_id = r.json()["id"]
        CREATED["supplier"] = supplier_id

    test("POST /suppliers — 创建供应商", create_supplier)

    def list_suppliers():
        r = requests.get(f"{BASE}/bidding/suppliers", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /suppliers — 供应商列表", list_suppliers)

    def get_supplier():
        r = requests.get(f"{BASE}/bidding/suppliers/{supplier_id}", headers=h)
        assert r.status_code == 200

    test("GET /suppliers/{id} — 供应商详情", get_supplier)

    # ── Instructors ──
    print("\n===== Bidding: Instructors =====")
    instructor_id = None

    def create_instructor():
        nonlocal instructor_id
        r = requests.post(f"{BASE}/bidding/instructors", json={
            "name": "王教授",
            "supplier_id": supplier_id,
            "expertise": ["AI", "机器学习", "深度学习"],
            "tags": ["AI", "深度学习"],
            "qualifications": ["计算机博士", "15年AI研究经验"],
            "experience_years": 15,
            "courses_taught": ["AI基础", "深度学习实战"],
            "rating": 4.8
        }, headers=h)
        assert r.status_code == 200
        instructor_id = r.json()["id"]
        CREATED["instructor"] = instructor_id

    test("POST /instructors — 创建讲师", create_instructor)

    def list_instructors():
        r = requests.get(f"{BASE}/bidding/instructors", params={"limit": 10}, headers=h)
        assert r.status_code == 200

    test("GET /instructors — 讲师列表", list_instructors)

    # ── Course Match ──
    print("\n===== Bidding: Course Match =====")

    def match_course():
        r = requests.post(f"{BASE}/bidding/match-course", json={
            "course_name": "深度学习与AI应用实战",
            "requirements": "面向企业技术团队，需要讲师有丰富实战经验"
        }, headers=h, timeout=120)
        assert r.status_code == 200, f"Match course failed: {r.status_code} {r.text}"

    test("POST /match-course — LLM课程匹配", match_course)

    # ═══════════════════════════════════════════
    # CLEANUP
    # ═══════════════════════════════════════════
    print("\n===== Cleanup =====")
    # Cleanup in reverse dependency order
    cleanup_map = {
        "instructor": ("/bidding/instructors/", "讲师"),
        "supplier": ("/bidding/suppliers/", "供应商"),
        "process": ("/bidding/processes/", "流程"),
        "knowledge_doc": ("/bidding/knowledge/docs/", "招投标文档"),
        "knowledge_dir": ("/bidding/knowledge/dirs/", "目录"),
        "contract": ("/bidding/contracts/", "合同"),
        "template": ("/bidding/templates/", "模板"),
        "knowledge_entry": ("/marketing/knowledge/", "知识条目"),
        "proposal": ("/marketing/proposals/", "方案"),
        "project": ("/marketing/projects/", "项目"),
        "customer": ("/marketing/customers/", "客户"),
    }

    for key, (prefix, label) in cleanup_map.items():
        if key in CREATED:
            try:
                r = requests.delete(f"{BASE}{prefix}{CREATED[key]}", headers=h)
                if r.status_code == 200:
                    print(f"  Deleted {label}: {CREATED[key]}")
                else:
                    print(f"  Delete {label} ({CREATED[key]}): {r.status_code} {r.text}")
            except Exception as e:
                print(f"  Delete {label} failed: {e}")

    print(f"\n{'='*50}")
    print(f"Results: {PASSED} passed, {FAILED} failed, {PASSED+FAILED} total")
    print(f"{'='*50}")

    return FAILED == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
