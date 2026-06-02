# 预算总览卡片

**日期**: 2026-06-01

## 功能

预算页面顶部一个汇总卡片，显示所有活跃预算的总计。点击展开显示分类明细。

## 数据

### Backend: 新增 API `GET /finance/budgets/summary`

返回：
```json
{
  "total_budget": 660000.0,
  "total_used": 283500.0,
  "items": [
    {"name": "办公费", "budget": 500000, "used": 238000, "color": "#4F46E5"},
    {"name": "差旅费", "budget": 80000, "used": 45000, "color": "#F59E0B"},
    ...
  ],
  "unallocated": 260000.0,
  "uncategorized_used": 15000.0
}
```

- `unallocated`: 所有活跃预算的总额 - 各分类预算项的金额之和（未分配部分）
- `uncategorized_used`: 没有归入任何预算分类的实际支出（如支出类别和预算分类不匹配的）

### 如果不想加后端 API

可以直接在前端用现有 `/finance/budgets` 数据聚合：
- `total_budget` = sum of all budget.total_amount
- `total_used` = sum of all budget.used_amount
- `items` = flatten all budget items across all budgets
- `unallocated` = total_budget - sum(items.amount)
- `uncategorized_used` = total_used - sum(items.used_amount)

## UI

### 收起状态（默认）

- 卡片显示：总计金额 + 棋盘格/彩色条
- 条下方迷你彩色指示线
- 点击展开

### 展开状态

- 卡片原位扩展开
- 每个分类的明细条（棋盘格+彩色）
- "未分配预算"行：灰色虚线条
- "未归类支出"行：灰色棋盘格条
- 点击收起

## 与后端联动

- 页面加载时刷新 summary 数据
- 创建/编辑/删除预算后自动刷新
- 创建支出后自动刷新（已通过 recalc）
