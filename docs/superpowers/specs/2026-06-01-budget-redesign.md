# 预算管理重写

**日期**: 2026-06-01

## 数据模型

Budget 已有 parent_id（自引用 FK）。四级树：总预算 → 季度 → 部门 → 分类项(BudgetItem)。

## 创建流程

1. 创建预算池：名称、年度、季度(可选)、总额、部门(可选)
2. 卡片菜单 → "创建子项" → 创建子预算（自动设 parent_id）
3. 叶子预算 → "添加分类" → 添加 BudgetItem

## 隔离规则

支出匹配预算条件：
- **有部门预算**：department_id 完全匹配 AND 日期在 year+quarter 范围内
- **无部门预算（父级）**：汇总该时段内**所有部门**的支出，不区分部门
- 未匹配到具体部门的支出 → 计入对应时段无部门预算的"未分类"

匹配后再按 category 分配到 BudgetItem。

## 支出传导（B方案）

一笔支出在匹配的预算层级上**向上逐层传导**：

```
2026总预算 (used = sum of children)
├── Q1 (used = sum of children)
│   └── 技术部 (used = matched expenses by category)
```

实现：`_recalc_budget_usage` 先更新叶子层 used_amount，然后自底向上 sum children → parent.used_amount。

## 前端

- 树形视图：根节点 → 子节点缩进24px → 孙节点缩进48px
- 折叠/展开卡片
- 子节点左侧显示层级标签（季/部）
- 每层棋盘格进度条
- 总览卡片（顶部）
- "创建子项"在父卡片菜单中
- "添加分类"在叶子卡片详情中

## 不改变

- 票据/支出/凭证模块
- Dashboard
- 侧边栏/主题
- 后端其他API
