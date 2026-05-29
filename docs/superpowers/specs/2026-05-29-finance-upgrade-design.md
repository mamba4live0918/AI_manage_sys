# Finance Module Upgrade — 设计文档

**日期**: 2026-05-29
**状态**: 待实现

## 目标

扩展财务模块：增加合同到收款链路、预算管控、财务 Dashboard，当前仅有结算/报销/凭证基础 CRUD。

## 一、合同到收款链路

### 新增模型

**Invoice（发票）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | — |
| project_id | UUID FK → pm_projects | 关联项目 |
| invoice_no | string(128) | 发票号 |
| amount | float | 发票金额 |
| tax_amount | float | 税额 |
| tax_rate | float | 税率（默认0.13） |
| status | string(32) | draft/issued/paid/partial/void |
| issue_date | datetime | 开票日期 |
| due_date | datetime | 到期日 |
| notes | text | 备注 |
| department_id | UUID FK → departments | 部门隔离 |
| created_by | UUID FK → users | — |
| created_at / updated_at | datetime | 自动时间戳 |

**Payment（收款）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | — |
| invoice_id | UUID FK → invoices | 关联发票 |
| amount | float | 收款金额 |
| payment_date | datetime | 收款日期 |
| payment_method | string(32) | bank_transfer/cash/cheque/other |
| ref_no | string(128) | 银行流水号 |
| notes | text | 备注 |
| department_id | UUID FK → departments | — |
| created_by | UUID FK → users | — |
| created_at / updated_at | datetime | — |

### Settlement 扩展

现有 Settlement 增加 `invoice_id` 字段（UUID FK → invoices，可选）。

### API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/finance/invoices | 发票列表（支持 project_id/status 筛选） |
| POST | /api/finance/invoices | 创建发票 |
| PUT | /api/finance/invoices/{id} | 更新发票 |
| DELETE | /api/finance/invoices/{id} | 删除发票 |
| GET | /api/finance/payments | 收款列表（支持 invoice_id 筛选） |
| POST | /api/finance/payments | 创建收款（自动更新发票状态：金额够→paid，部分→partial） |
| DELETE | /api/finance/payments/{id} | 删除收款（自动回退发票状态） |

### 发票总额与收款联动

- 创建收款时，汇总该发票下所有收款金额
- 汇总 ≥ 发票金额 → 发票 status 自动变 `paid`
- 汇总 > 0 且 < 发票金额 → 发票 status 变 `partial`
- 删除收款时重新计算发票状态

---

## 二、预算管控

### 新增模型

**Budget（预算）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| id | UUID PK | — |
| department_id | UUID FK → departments | 所属部门 |
| project_id | UUID FK → pm_projects（nullable） | null=部门预算，有值=项目预算 |
| name | string(128) | 预算名称 |
| year | int | 预算年度 |
| quarter | int（nullable） | 季度，null=全年 |
| total_amount | float | 预算总额 |
| used_amount | float | 已用金额（自动计算） |
| status | string(32) | active/frozen/closed |
| created_by | UUID FK → users | — |
| created_at / updated_at | datetime | — |

### API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/finance/budgets | 预算列表（支持 department_id/year 筛选） |
| POST | /api/finance/budgets | 创建预算（项目预算校验不超过部门预算） |
| PUT | /api/finance/budgets/{id} | 更新预算 |
| DELETE | /api/finance/budgets/{id} | 删除预算 |

### used_amount 计算逻辑

- `used_amount` = 该部门/项目下所有已审批报销金额 + 已结算金额的汇总
- 每次报销审批通过/结算创建/结算删除时自动重算
- **超预算警告**：创建报销时如果 `used_amount + 本次金额 > total_amount`，正常创建但 API 响应里额外返回 `{"budget_warning": true}`，前端弹提示

---

## 三、财务 Dashboard

### API: GET /api/finance/dashboard

权限：`require_module("finance")`

返回字段：

```json
{
  "monthly_revenue": 123456.0,
  "total_receivable": 234567.0,
  "collection_rate": 0.85,
  "budget_usage": [
    {"name": "项目A", "total": 500000, "used": 320000}
  ],
  "revenue_trend_12m": [
    {"month": "2025-06", "revenue": 12345},
    ...
  ],
  "pending_invoices": 3,
  "pending_payments": 12,
  "pending_expenses": 5
}
```

- `monthly_revenue`：本月收款总额
- `total_receivable`：所有未完全收款的发票金额合计 - 已收金额合计
- `collection_rate`：已收总额 / 已开发票总额
- `budget_usage`：所有活跃预算的使用情况（按 used/total 降序）
- `revenue_trend_12m`：过去12个月每月收款总额
- `pending_*`：待开票数 / 待收款数 / 待审批报销数

### Flutter 页面改造

- **finance_dashboard_page.dart** 重写：KPI 卡片 + 预算进度条 + 收入趋势折线图 + 待处理清单
- 新增 **invoice_list_page.dart**：发票列表 + 创建 + 详情
- 新增 **payment_list_page.dart**：收款列表 + 创建
- 新增 **budget_page.dart**：预算列表 + 创建/编辑
- 现有 settlement/expense/voucher 页面保留
- Provider 模式：`FinanceDashboardProvider`、`FinanceInvoiceProvider`、`FinanceBudgetProvider`
- 实时更新：页面进入加载 → 下拉刷新 → 创建/修改操作后 `ref.invalidate()` 触发重载

---

## 数据模型关系

```
Department ──→ Budget (部门预算)
   │                │
   │                └──→ Budget (项目预算，project_id 有值)
   │
   └──→ Project ──→ Invoice (多张)
                         │
                         └──→ Payment (多次收款)
                         
Expense ──→ Settlement ──→ Invoice (可选关联)
```

## 降级策略

所有新功能不影响现有结算/报销/凭证功能。Invoice/Payment/Budget 为可选模块，前端可通过 Tab 切换访问。
