"""Phase 4 E2E Tests — PM + HR + Finance full API coverage"""
import requests
import sys

BASE = "http://localhost:8001/api"
PASSED = 0
FAILED = 0
CREATED = {}

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
    # PM
    # ═══════════════════════════════════════════

    # ── Projects ──
    print("\n===== PM: Projects =====")
    project_id = None

    def create_project():
        nonlocal project_id
        r = requests.post(f"{BASE}/pm/projects", json={
            "name": "E2E测试项目",
            "stage": "initiation",
            "budget": 500000.0,
            "description": "自动化测试项目"
        }, headers=h)
        assert r.status_code == 200, f"Create project failed: {r.text}"
        project_id = r.json()["id"]
        CREATED["project"] = project_id

    test("POST /pm/projects — create", create_project)

    def list_projects():
        r = requests.get(f"{BASE}/pm/projects", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /pm/projects — list", list_projects)

    def get_project():
        r = requests.get(f"{BASE}/pm/projects/{project_id}", headers=h)
        assert r.status_code == 200
        assert r.json()["name"] == "E2E测试项目"

    test("GET /pm/projects/{id} — get", get_project)

    def update_project():
        r = requests.put(f"{BASE}/pm/projects/{project_id}", json={
            "name": "E2E测试项目(已更新)",
            "stage": "planning",
            "budget": 600000.0
        }, headers=h)
        assert r.status_code == 200
        assert r.json()["stage"] == "planning"

    test("PUT /pm/projects/{id} — update", update_project)

    def filter_by_stage():
        r = requests.get(f"{BASE}/pm/projects", params={"stage": "planning", "limit": 10}, headers=h)
        assert r.status_code == 200
        for item in r.json()["items"]:
            assert item["stage"] == "planning"

    test("GET /pm/projects?stage=planning — filter", filter_by_stage)

    # ── PM Stats ──
    print("\n===== PM: Stats =====")

    def get_pm_stats():
        r = requests.get(f"{BASE}/pm/stats", headers=h)
        assert r.status_code == 200, f"Get PM stats failed: {r.text}"
        data = r.json()
        assert "total_projects" in data
        assert "total_budget" in data
        assert "stages" in data
        assert "projects_budget" in data
        assert "calendar_events" in data
        assert data["total_projects"] >= 1

    test("GET /pm/stats — charts/calendar data", get_pm_stats)

    # ── Visit Logs ──
    print("\n===== PM: Visit Logs =====")
    log_id = None

    def create_visit_log():
        nonlocal log_id
        r = requests.post(f"{BASE}/pm/projects/{project_id}/logs", json={
            "content": "客户需求沟通",
            "location": "客户办公室"
        }, headers=h)
        assert r.status_code == 200, f"Create log failed: {r.text}"
        log_id = r.json()["id"]

    test("POST /pm/projects/{id}/logs — create log", create_visit_log)

    def list_visit_logs():
        r = requests.get(f"{BASE}/pm/projects/{project_id}/logs", headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /pm/projects/{id}/logs — list logs", list_visit_logs)

    # ── Project Report (LLM) ──
    print("\n===== PM: Project Reports =====")

    def generate_report():
        r = requests.post(f"{BASE}/pm/projects/{project_id}/report", json={
            "report_type": "progress"
        }, headers=h)
        assert r.status_code == 200, f"Generate report failed: {r.text}"
        assert len(r.json()["content"]) > 0
        CREATED["report"] = r.json()["id"]

    test("POST /pm/projects/{id}/report — generate LLM report", generate_report)

    # ── Coursewares ──
    print("\n===== PM: Coursewares =====")
    courseware_id = None

    def create_courseware():
        nonlocal courseware_id
        r = requests.post(f"{BASE}/pm/coursewares", json={
            "title": "E2E测试课件",
            "type": "document",
            "content": "# 课件内容\n自动化测试课件",
            "project_id": project_id
        }, headers=h)
        assert r.status_code == 200, f"Create courseware failed: {r.text}"
        courseware_id = r.json()["id"]
        CREATED["courseware"] = courseware_id

    test("POST /pm/coursewares — create courseware", create_courseware)

    def list_coursewares():
        r = requests.get(f"{BASE}/pm/coursewares", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /pm/coursewares — list coursewares", list_coursewares)

    def get_courseware():
        r = requests.get(f"{BASE}/pm/coursewares/{courseware_id}", headers=h)
        assert r.status_code == 200
        assert r.json()["title"] == "E2E测试课件"

    test("GET /pm/coursewares/{id} — get courseware", get_courseware)

    def update_courseware():
        r = requests.put(f"{BASE}/pm/coursewares/{courseware_id}", json={
            "title": "E2E测试课件(已更新)",
            "content": "# 更新后的内容"
        }, headers=h)
        assert r.status_code == 200
        assert r.json()["title"] == "E2E测试课件(已更新)"

    test("PUT /pm/coursewares/{id} — update courseware", update_courseware)

    def filter_coursewares_by_project():
        r = requests.get(f"{BASE}/pm/coursewares", params={"project_id": project_id}, headers=h)
        assert r.status_code == 200

    test("GET /pm/coursewares?project_id= — filter by project", filter_coursewares_by_project)

    def _pdf_bytes():
        # minimal valid PDF
        return b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Count 0>>endobj xref\n0 2\n0000000000 65535 f \n0000000009 00000 n \ntrailer<</Size 2/Root 1 0 R>>startxref\n%%EOF"

    def upload_courseware():
        nonlocal courseware_id
        r = requests.post(f"{BASE}/pm/coursewares/upload", files={
            'file': ('test_cw.pdf', _pdf_bytes(), 'application/pdf')
        }, data={'title': '上传测试课件', 'type': 'slides'}, headers=h)
        assert r.status_code == 200, f"Upload courseware failed: {r.text}"
        assert r.json()['file_id'] is not None

    test("POST /pm/coursewares/upload — upload PDF courseware", upload_courseware)

    # ═══════════════════════════════════════════
    # HR
    # ═══════════════════════════════════════════

    # ── Employees ──
    print("\n===== HR: Employees =====")
    employee_id = None

    def create_employee():
        nonlocal employee_id
        r = requests.post(f"{BASE}/hr/employees", json={
            "name": "E2E测试员工",
            "position": "软件工程师",
            "phone": "13900139000",
            "email": "test_emp@company.com",
            "status": "active",
            "notes": "自动化测试员工"
        }, headers=h)
        assert r.status_code == 200, f"Create employee failed: {r.text}"
        employee_id = r.json()["id"]
        CREATED["employee"] = employee_id

    test("POST /hr/employees — create employee", create_employee)

    def list_employees():
        r = requests.get(f"{BASE}/hr/employees", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /hr/employees — list employees", list_employees)

    def get_employee():
        r = requests.get(f"{BASE}/hr/employees/{employee_id}", headers=h)
        assert r.status_code == 200
        assert r.json()["name"] == "E2E测试员工"

    test("GET /hr/employees/{id} — get employee", get_employee)

    def update_employee():
        r = requests.put(f"{BASE}/hr/employees/{employee_id}", json={
            "name": "E2E测试员工(已更新)",
            "position": "高级工程师",
            "status": "probation"
        }, headers=h)
        assert r.status_code == 200
        assert r.json()["status"] == "probation"

    test("PUT /hr/employees/{id} — update employee", update_employee)

    def filter_employees_by_status():
        r = requests.get(f"{BASE}/hr/employees", params={"status": "probation"}, headers=h)
        assert r.status_code == 200
        for item in r.json()["items"]:
            assert item["status"] == "probation"

    test("GET /hr/employees?status=probation — filter", filter_employees_by_status)

    # ── Resumes ──
    print("\n===== HR: Resumes =====")
    resume_id = None

    def create_resume():
        nonlocal resume_id
        r = requests.post(f"{BASE}/hr/resumes", json={
            "name": "张三",
            "content": "10年Java开发经验，精通Spring Boot微服务架构，曾负责大型电商平台后端开发...",
            "status": "new"
        }, headers=h)
        assert r.status_code == 200, f"Create resume failed: {r.text}"
        resume_id = r.json()["id"]
        CREATED["resume"] = resume_id

    test("POST /hr/resumes — create resume", create_resume)

    def list_resumes():
        r = requests.get(f"{BASE}/hr/resumes", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /hr/resumes — list resumes", list_resumes)

    def get_resume():
        r = requests.get(f"{BASE}/hr/resumes/{resume_id}", headers=h)
        assert r.status_code == 200
        assert r.json()["name"] == "张三"

    test("GET /hr/resumes/{id} — get resume", get_resume)

    def update_resume():
        r = requests.put(f"{BASE}/hr/resumes/{resume_id}", json={
            "status": "reviewing"
        }, headers=h)
        assert r.status_code == 200

    test("PUT /hr/resumes/{id} — update resume", update_resume)

    def match_resume():
        r = requests.post(f"{BASE}/hr/resumes/{resume_id}/match", headers=h)
        assert r.status_code == 200, f"Match resume failed: {r.text}"
        assert r.json()["match_score"] > 0
        assert len(r.json()["match_result"]) > 0

    test("POST /hr/resumes/{id}/match — LLM match resume", match_resume)

    # ── Approvals ──
    print("\n===== HR: Approvals =====")
    approval_id = None

    def create_approval():
        nonlocal approval_id
        r = requests.post(f"{BASE}/hr/approvals", json={
            "approval_type": "leave",
            "content": "年假申请，5天"
        }, headers=h)
        assert r.status_code == 200, f"Create approval failed: {r.text}"
        data = r.json()
        approval_id = data["id"]
        CREATED["approval"] = approval_id
        steps = data.get("steps", [])
        assert len(steps) == 2, f"Expected 2 steps for leave, got {len(steps)}"
        assert all(s["status"] == "pending" for s in steps)

    test("POST /hr/approvals — create with 2 auto-steps", create_approval)

    def list_approvals():
        r = requests.get(f"{BASE}/hr/approvals", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        items = r.json()["items"]
        assert len(items) > 0
        assert "steps" in items[0]

    test("GET /hr/approvals — list with steps", list_approvals)

    def get_approval_detail():
        r = requests.get(f"{BASE}/hr/approvals/{approval_id}", headers=h)
        assert r.status_code == 200
        assert "steps" in r.json()

    test("GET /hr/approvals/{id} — detail with steps", get_approval_detail)

    def approve_first_step():
        r = requests.get(f"{BASE}/hr/approvals/{approval_id}", headers=h)
        steps = r.json()["steps"]
        step1 = steps[0]
        r2 = requests.put(f"{BASE}/hr/approvals/{approval_id}/steps/{step1['id']}", json={
            "status": "approved", "comment": "一级同意"
        }, headers=h)
        assert r2.status_code == 200
        assert r2.json()["status"] == "pending"  # still pending because step2 not done

    test("PUT /hr/approvals/{id}/steps/{step_id} — approve step 1", approve_first_step)

    def approve_second_step():
        r = requests.get(f"{BASE}/hr/approvals/{approval_id}", headers=h)
        steps = r.json()["steps"]
        step2 = steps[1]
        r2 = requests.put(f"{BASE}/hr/approvals/{approval_id}/steps/{step2['id']}", json={
            "status": "approved", "comment": "二级同意"
        }, headers=h)
        assert r2.status_code == 200
        assert r2.json()["status"] == "approved"  # all steps done

    test("PUT /hr/approvals/{id}/steps/{step_id} — approve step 2 completes", approve_second_step)

    def filter_approvals_by_status():
        r = requests.get(f"{BASE}/hr/approvals", params={"status": "approved"}, headers=h)
        assert r.status_code == 200

    test("GET /hr/approvals?status=approved — filter", filter_approvals_by_status)

    def filter_approvals_by_type():
        r = requests.get(f"{BASE}/hr/approvals", params={"approval_type": "leave"}, headers=h)
        assert r.status_code == 200

    test("GET /hr/approvals?approval_type=leave — filter by type", filter_approvals_by_type)

    # Test rejection flow
    approval_id2 = None

    def create_and_reject():
        nonlocal approval_id2
        r = requests.post(f"{BASE}/hr/approvals", json={
            "approval_type": "expense",
            "content": "差旅费报销，3000元"
        }, headers=h)
        assert r.status_code == 200
        data = r.json()
        approval_id2 = data["id"]
        steps = data.get("steps", [])
        assert len(steps) == 3, f"Expected 3 steps for expense, got {len(steps)}"
        step1 = steps[0]
        r2 = requests.put(f"{BASE}/hr/approvals/{approval_id2}/steps/{step1['id']}", json={
            "status": "rejected", "comment": "金额超限"
        }, headers=h)
        assert r2.status_code == 200
        assert r2.json()["status"] == "rejected"

    test("POST + PUT steps — expense 3-level rejection cascade", create_and_reject)

    def delete_approval2():
        r = requests.delete(f"{BASE}/hr/approvals/{approval_id2}", headers=h)
        assert r.status_code == 200

    test("DELETE /hr/approvals/{id} — cleanup rejected", delete_approval2)

    # ═══════════════════════════════════════════
    # FINANCE
    # ═══════════════════════════════════════════

    # ── Settlements ──
    print("\n===== Finance: Settlements =====")
    settlement_id = None

    def create_settlement():
        nonlocal settlement_id
        r = requests.post(f"{BASE}/finance/settlements", json={
            "amount": 100000.0,
            "invoice_no": "INV-2026-001",
            "notes": "E2E测试结算",
            "project_id": project_id
        }, headers=h)
        assert r.status_code == 200, f"Create settlement failed: {r.text}"
        settlement_id = r.json()["id"]
        CREATED["settlement"] = settlement_id

    test("POST /finance/settlements — create settlement", create_settlement)

    def list_settlements():
        r = requests.get(f"{BASE}/finance/settlements", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /finance/settlements — list settlements", list_settlements)

    def get_settlement():
        r = requests.get(f"{BASE}/finance/settlements/{settlement_id}", headers=h)
        assert r.status_code == 200
        assert r.json()["amount"] == 100000.0

    test("GET /finance/settlements/{id} — get settlement", get_settlement)

    def update_settlement():
        r = requests.put(f"{BASE}/finance/settlements/{settlement_id}", json={
            "status": "completed",
            "amount": 120000.0
        }, headers=h)
        assert r.status_code == 200
        assert r.json()["status"] == "completed"

    test("PUT /finance/settlements/{id} — update settlement", update_settlement)

    def filter_settlements_by_status():
        r = requests.get(f"{BASE}/finance/settlements", params={"status": "completed"}, headers=h)
        assert r.status_code == 200

    test("GET /finance/settlements?status=completed — filter", filter_settlements_by_status)

    # ── Expenses ──
    print("\n===== Finance: Expenses =====")
    expense_id = None

    def create_expense():
        nonlocal expense_id
        r = requests.post(f"{BASE}/finance/expenses", json={
            "amount": 5000.0,
            "category": "travel",
            "description": "出差报销",
            "project_id": project_id
        }, headers=h)
        assert r.status_code == 200, f"Create expense failed: {r.text}"
        expense_id = r.json()["id"]
        CREATED["expense"] = expense_id

    test("POST /finance/expenses — create expense", create_expense)

    def list_expenses():
        r = requests.get(f"{BASE}/finance/expenses", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /finance/expenses — list expenses", list_expenses)

    def approve_expense():
        r = requests.put(f"{BASE}/finance/expenses/{expense_id}", json={
            "status": "approved"
        }, headers=h)
        assert r.status_code == 200
        assert r.json()["status"] == "approved"

    test("PUT /finance/expenses/{id} — approve expense", approve_expense)

    def filter_expenses_by_category():
        r = requests.get(f"{BASE}/finance/expenses", params={"category": "travel"}, headers=h)
        assert r.status_code == 200

    test("GET /finance/expenses?category=travel — filter", filter_expenses_by_category)

    # ── Vouchers ──
    print("\n===== Finance: Vouchers =====")
    voucher_id = None

    def create_voucher():
        nonlocal voucher_id
        r = requests.post(f"{BASE}/finance/vouchers", json={
            "type": "invoice",
            "description": "发票凭证",
            "settlement_id": settlement_id
        }, headers=h)
        assert r.status_code == 200, f"Create voucher failed: {r.text}"
        voucher_id = r.json()["id"]
        CREATED["voucher"] = voucher_id

    test("POST /finance/vouchers — create voucher", create_voucher)

    def list_vouchers():
        r = requests.get(f"{BASE}/finance/vouchers", params={"limit": 10}, headers=h)
        assert r.status_code == 200
        assert len(r.json()["items"]) > 0

    test("GET /finance/vouchers — list vouchers", list_vouchers)

    def filter_vouchers_by_settlement():
        r = requests.get(f"{BASE}/finance/vouchers", params={"settlement_id": settlement_id}, headers=h)
        assert r.status_code == 200

    test("GET /finance/vouchers?settlement_id= — filter", filter_vouchers_by_settlement)

    def upload_voucher():
        r = requests.post(f"{BASE}/finance/vouchers/upload", files={
            'file': ('inv.pdf', _pdf_bytes(), 'application/pdf')
        }, data={'type': 'receipt', 'description': '上传测试凭证'}, headers=h)
        assert r.status_code == 200, f"Upload voucher failed: {r.text}"
        assert r.json()['file_id'] is not None

    test("POST /finance/vouchers/upload — upload PDF voucher", upload_voucher)

    # ═══════════════════════════════════════════
    # CLEANUP
    # ═══════════════════════════════════════════
    print("\n===== Cleanup =====")

    def delete_voucher():
        r = requests.delete(f"{BASE}/finance/vouchers/{voucher_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /finance/vouchers/{id}", delete_voucher)

    def delete_settlement():
        r = requests.delete(f"{BASE}/finance/settlements/{settlement_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /finance/settlements/{id}", delete_settlement)

    def delete_expense():
        r = requests.delete(f"{BASE}/finance/expenses/{expense_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /finance/expenses/{id}", delete_expense)

    def delete_courseware():
        r = requests.delete(f"{BASE}/pm/coursewares/{courseware_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /pm/coursewares/{id}", delete_courseware)

    def delete_project():
        r = requests.delete(f"{BASE}/pm/projects/{project_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /pm/projects/{id}", delete_project)

    def delete_employee():
        r = requests.delete(f"{BASE}/hr/employees/{employee_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /hr/employees/{id}", delete_employee)

    def delete_resume():
        r = requests.delete(f"{BASE}/hr/resumes/{resume_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /hr/resumes/{id}", delete_resume)

    def delete_approval():
        r = requests.delete(f"{BASE}/hr/approvals/{approval_id}", headers=h)
        assert r.status_code == 200

    test("DELETE /hr/approvals/{id}", delete_approval)

    # ═══════════════════════════════════════════
    print(f"\n{'='*50}")
    print(f"Results: {PASSED} passed, {FAILED} failed (total {PASSED + FAILED})")
    print(f"{'='*50}")
    return FAILED == 0

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
