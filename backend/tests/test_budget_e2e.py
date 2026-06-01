"""
E2E tests for the budget module.

Run:  pytest tests/test_budget_e2e.py -v
Requires: backend running on http://localhost:8001
"""

import pytest
import httpx
import uuid

BASE = "http://localhost:8001/api"
ADMIN_CREDS = {"username": "admin", "password": "admin123"}


@pytest.fixture(scope="module")
def client():
    """Authenticated httpx client."""
    with httpx.Client(timeout=30) as c:
        resp = c.post(f"{BASE}/auth/login", json=ADMIN_CREDS)
        assert resp.status_code == 200, f"Login failed: {resp.text}"
        token = resp.json()["access_token"]
        c.headers["Authorization"] = f"Bearer {token}"
        yield c


def delete_budget(client, bid):
    client.delete(f"{BASE}/finance/budgets/{bid}")


# ── 1. Budget CRUD ──


def test_create_root_budget(client):
    """Create a simple root budget and verify."""
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-根预算", "year": 2026, "total_amount": 100000, "status": "active",
    })
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["name"] == "E2E-根预算"
    assert data["total_amount"] == 100000
    assert data["parent_id"] is None
    delete_budget(client, data["id"])


def test_create_budget_with_items(client):
    """Create a budget with items and verify total is auto-calculated."""
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-带项目预算", "year": 2026, "quarter": 1, "status": "active",
        "items": [
            {"category": "office", "name": "办公用品", "amount": 30000, "color": "#4CAF50", "icon": "devices"},
            {"category": "travel", "name": "差旅费", "amount": 20000, "color": "#FF9800", "icon": "flight"},
        ],
    })
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["total_amount"] == 50000, f"Auto total should be 50000, got {data['total_amount']}"
    assert len(data["items"]) == 2
    delete_budget(client, data["id"])


def test_update_budget(client):
    """Update budget name and status."""
    # Create
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-更新前", "year": 2026, "total_amount": 50000, "status": "active",
    })
    bid = resp.json()["id"]

    # Update
    resp = client.put(f"{BASE}/finance/budgets/{bid}", json={
        "name": "E2E-更新后", "status": "frozen",
    })
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["name"] == "E2E-更新后"
    assert data["status"] == "frozen"

    delete_budget(client, bid)


def test_delete_budget_cascades(client):
    """Deleting a budget removes it."""
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-待删除", "year": 2026, "total_amount": 10000, "status": "active",
    })
    bid = resp.json()["id"]

    resp = client.delete(f"{BASE}/finance/budgets/{bid}")
    assert resp.status_code == 200

    # Verify gone
    resp = client.get(f"{BASE}/finance/budgets")
    ids = [b["id"] for b in resp.json()["items"]]
    assert bid not in ids


# ── 2. Tree Hierarchy ──


def test_tree_hierarchy_parent_child(client):
    """Create a parent → child → grandchild tree and verify parent_id chain."""
    # Root
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-树根", "year": 2026, "total_amount": 100000, "status": "active",
    })
    root_id = resp.json()["id"]

    # Quarter child
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-Q1", "year": 2026, "quarter": 1, "total_amount": 60000, "status": "active",
        "parent_id": root_id,
    })
    q1_id = resp.json()["id"]
    assert resp.json()["parent_id"] == root_id

    # Department grandchild under Q1
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-Q1技术部", "year": 2026, "quarter": 1, "total_amount": 40000, "status": "active",
        "parent_id": q1_id,
    })
    dept_id = resp.json()["id"]
    assert resp.json()["parent_id"] == q1_id

    # Verify tree by listing
    resp = client.get(f"{BASE}/finance/budgets")
    items = {b["id"]: b for b in resp.json()["items"]}
    assert items[dept_id]["parent_id"] == q1_id
    assert items[q1_id]["parent_id"] == root_id
    assert items[root_id]["parent_id"] is None

    # Cleanup (delete root cascades children)
    delete_budget(client, dept_id)
    delete_budget(client, q1_id)
    delete_budget(client, root_id)


# ── 3. Parent Budget Constraint ──


def test_child_sum_cannot_exceed_parent(client):
    """Creating children whose total exceeds parent should fail."""
    # Parent
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-父约束", "year": 2026, "total_amount": 50000, "status": "active",
    })
    pid = resp.json()["id"]

    # Child 1: 30000 (OK)
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-子1", "year": 2026, "quarter": 1, "total_amount": 30000, "status": "active",
        "parent_id": pid,
    })
    assert resp.status_code == 200, f"Child 1 should succeed: {resp.text}"
    c1_id = resp.json()["id"]

    # Child 2: 25000 (30000 + 25000 = 55000 > 50000, should FAIL)
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-子2", "year": 2026, "quarter": 2, "total_amount": 25000, "status": "active",
        "parent_id": pid,
    })
    assert resp.status_code == 400, f"Child 2 should fail: {resp.text}"
    assert "超过父预算" in resp.json()["detail"]

    # Cleanup
    delete_budget(client, c1_id)
    delete_budget(client, pid)


# ── 4. Update Constraint ──


def test_update_parent_below_children_sum(client):
    """Reducing parent total below sum of children should fail."""
    # Parent
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-更新约束父", "year": 2026, "total_amount": 80000, "status": "active",
    })
    pid = resp.json()["id"]

    # Child
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-更新约束子", "year": 2026, "quarter": 1, "total_amount": 60000, "status": "active",
        "parent_id": pid,
    })
    cid = resp.json()["id"]

    # Try to reduce parent to 40000 (less than child's 60000)
    resp = client.put(f"{BASE}/finance/budgets/{pid}", json={"total_amount": 40000})
    assert resp.status_code == 400, f"Should fail: {resp.text}"
    assert "不能小于子预算总和" in resp.json()["detail"]

    # Cleanup
    delete_budget(client, cid)
    delete_budget(client, pid)


# ── 5. Budget Items ──


def test_add_budget_items(client):
    """Add items to a budget and verify."""
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-项目测试", "year": 2026, "total_amount": 100000, "status": "active",
    })
    bid = resp.json()["id"]

    # Update with items
    resp = client.put(f"{BASE}/finance/budgets/{bid}", json={
        "items": [
            {"category": "equipment", "name": "服务器", "amount": 50000, "color": "#009688", "icon": "devices"},
            {"category": "salary", "name": "工资", "amount": 30000, "color": "#E91E63", "icon": "monetization_on"},
            {"category": "office", "name": "杂项", "amount": 20000, "color": "#2196F3", "icon": "description"},
        ],
    })
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert len(data["items"]) == 3
    assert data["total_amount"] == 100000

    delete_budget(client, bid)


# ── 6. Summary Endpoint ──


def test_budget_summary(client):
    """Summary endpoint returns aggregated data."""
    resp = client.get(f"{BASE}/finance/budgets/summary")
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert "total_budget" in data
    assert "total_used" in data
    assert isinstance(data["total_budget"], (int, float))


# ── 7. List with Filters ──


def test_list_budgets_filter_by_parent(client):
    """List budgets filtered by parent_id."""
    # Create parent
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-筛选父", "year": 2026, "total_amount": 80000, "status": "active",
    })
    pid = resp.json()["id"]

    # Create 2 children
    ids = []
    for i in range(2):
        resp = client.post(f"{BASE}/finance/budgets", json={
            "name": f"E2E-筛选子{i}", "year": 2026, "quarter": i + 1, "total_amount": 30000, "status": "active",
            "parent_id": pid,
        })
        ids.append(resp.json()["id"])

    # Filter by parent
    resp = client.get(f"{BASE}/finance/budgets", params={"parent_id": pid})
    assert resp.status_code == 200
    children = resp.json()["items"]
    assert len(children) == 2

    # Cleanup
    for cid in ids:
        delete_budget(client, cid)
    delete_budget(client, pid)


# ── 8. Budget Adjust ──


def test_adjust_budget_total(client):
    """Adjust budget total via update."""
    resp = client.post(f"{BASE}/finance/budgets", json={
        "name": "E2E-调整测试", "year": 2026, "total_amount": 50000, "status": "active",
    })
    bid = resp.json()["id"]

    # Increase
    resp = client.put(f"{BASE}/finance/budgets/{bid}", json={"total_amount": 70000})
    assert resp.status_code == 200
    assert resp.json()["total_amount"] == 70000

    delete_budget(client, bid)
