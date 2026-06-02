# Budget Redesign Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Rewrite budget module with tree hierarchy, department+quarter isolation, upward expense propagation, and chessboard-bar UI.

**Architecture:** Backend `_recalc_budget_usage` rewritten for correct matching + propagation. Frontend budget page rewritten as collapsible tree view. Existing Budget/BudgetItem models and parent_id field stay.

**Tech Stack:** FastAPI + SQLAlchemy + Flutter Riverpod + CustomPaint

---

### Task 1: Rewrite `_recalc_budget_usage` — correct matching + upward propagation

**Files:**
- Modify: `backend/app/api/finance.py:254-300`

Replace the entire `_recalc_budget_usage` function with correct logic:

```python
async def _recalc_budget_usage(db: AsyncSession):
    """Recalculate used_amount for all active budgets with correct isolation + propagation."""
    all_budgets = (await db.execute(select(Budget).where(Budget.status == "active"))).scalars().all()
    
    # Step 1: Calculate leaf-level used_amount (budgets with both department and quarter)
    for b in all_budgets:
        ym_start, ym_end = _budget_date_range(b)
        if not ym_start:
            continue  # no year set, skip
        
        conditions = [Expense.status.in_(["approved", "paid"])]
        conditions.append(Expense.created_at >= ym_start)
        conditions.append(Expense.created_at < ym_end)
        
        # Department matching: if budget has department, filter by it. If not, match ALL departments.
        if b.department_id is not None:
            conditions.append(Expense.department_id == b.department_id)
        
        # Sum expenses for this budget
        exp_total = (await db.execute(
            select(func.coalesce(func.sum(Expense.amount), 0.0)).where(*conditions)
        )).scalar() or 0.0
        
        # Also sum settlements
        stl_conditions = [Settlement.status.in_(["completed", "settled"])]
        stl_conditions.append(Settlement.created_at >= ym_start)
        stl_conditions.append(Settlement.created_at < ym_end)
        if b.department_id is not None:
            stl_conditions.append(Settlement.department_id == b.department_id)
        
        stl_total = (await db.execute(
            select(func.coalesce(func.sum(Settlement.amount), 0.0)).where(*stl_conditions)
        )).scalar() or 0.0
        
        b.used_amount = exp_total + stl_total
        
        # Per-item used_amount (category matching)
        items_result = await db.execute(select(BudgetItem).where(BudgetItem.budget_id == b.id))
        for item in items_result.scalars().all():
            item_cond = [
                Expense.status.in_(["approved", "paid"]),
                Expense.created_at >= ym_start,
                Expense.created_at < ym_end,
                Expense.category == item.category,
            ]
            if b.department_id is not None:
                item_cond.append(Expense.department_id == b.department_id)
            item.used_amount = (await db.execute(
                select(func.coalesce(func.sum(Expense.amount), 0.0)).where(*item_cond)
            )).scalar() or 0.0

    # Step 2: Propagate upward — parent used_amount = sum of children used_amount
    # Process budgets ordered by depth (leaves first, roots last)
    # Build a map of parent_id -> list of child budgets
    children_map: dict = {}
    for b in all_budgets:
        if b.parent_id:
            children_map.setdefault(str(b.parent_id), []).append(b)
    
    # Iteratively update parents until no more changes
    changed = True
    while changed:
        changed = False
        for b in all_budgets:
            if str(b.id) in children_map:
                children = children_map[str(b.id)]
                child_sum = sum(c.used_amount for c in children)
                if abs(b.used_amount - child_sum) > 0.01:
                    b.used_amount = child_sum
                    changed = True
    
    await db.commit()
```

Commit: `refactor: rewrite budget recalculation with correct isolation and upward propagation`

---

### Task 2: Rewrite budget page — tree view with collapsible cards

**Files:**
- Modify: `frontend/lib/pages/finance/finance_budget_page.dart`

Simplify the entire page. Keep only:

**State:**
- `_expandedNodes: Set<String>` — which nodes are expanded
- `_summary` + `_summaryExpanded` — summary card state
- Providers and API client (keep existing)

**Build method:**
```dart
@override
Widget build(BuildContext context) {
  final state = ref.watch(financeBudgetProvider);
  return Scaffold(
    appBar: AppBar(title: const Text('预算管理')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _showCreateDialog(context),
      child: const Icon(Icons.add),
    ),
    body: state.loading 
      ? const Center(child: CircularProgressIndicator())
      : RefreshIndicator(
          onRefresh: () async {
            ref.read(financeBudgetProvider.notifier).load();
            _loadSummary();
          },
          child: _buildBudgetTree(context, state.items),
        ),
  );
}
```

**_buildBudgetTree:**
- Summary card at top (if _summary != null)
- Group budgets by parent_id
- Render roots, then children indented
- Each card: name + quarter/department tags + chessboard bar + expand chevron + popup menu

**_buildBudgetCard:**
- InkWell toggles expand/collapse
- Shows chessboard progress bar (use `_DashCheckerPainter` from finance dashboard, copy the painter class to this file)
- PopupMenu: 编辑 / 创建子项 / 调整 / 删除
- isChild cards show "季" or "部" tag

**Create dialog:** `_showCreateDialog(BuildContext context, {String? parentId})` — simple form: name, year, quarter, total_amount, department (auto-filled from user), status. If parentId != null, auto-set parent_id.

**Delete budget:** Delete self + all children (backend cascade handles this).

**Import:**
```dart
import 'package:fl_chart/fl_chart.dart';  // remove if not used
import '../../config/theme.dart';
```

Commit: `refactor: rewrite budget page as clean tree view with collapsible cards`

---

### Task 3: Verify and test

**Files:**
- No new files, manual verification

- [ ] **Step 1: Restart backend**
```bash
docker compose up -d
cd backend && python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

- [ ] **Step 2: Build and launch**
```bash
cd frontend && flutter build windows
start build\windows\x64\runner\Release\ai_manage_sys.exe
```

- [ ] **Step 3: Manual test**
  - Create a parent budget (2026, no quarter, no department)
  - Create child budget under it (Q2, no department)
  - Create grandchild budget (Q2, 技术部)
  - Add category item to grandchild
  - Create a direct expense (办公费, 技术部 dept)
  - Verify: grandchild shows used_amount, parent aggregates upward, other department budgets not affected

- [ ] **Step 4: Commit any fixes if needed**
```bash
git add -A && git commit -m "fix: budget tree fixes from testing"
```
