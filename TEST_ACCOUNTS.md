# AI 管理系统 — 账号 & 功能说明

## 测试账号

| 用户名 | 密码 | 部门 | 可访问模块 |
|--------|------|------|-----------|
| admin | admin123 | 技术部 | 全部 |
| finance | finance123 | 财务部 | 首页、文件、支出报销、财务 |
| tech | tech123 | 技术部 | 首页、文件、支出报销、招投标、项目管理 |
| mkt | mkt123 | 市场部 | 首页、文件、支出报销、市场部 |
| hr | hr123 | 人力资源部 | 首页、文件、支出报销、HR |

## 启动方式

```bash
# 1. 基础设施
docker compose up -d

# 2. 后端
cd backend
python -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

# 3. 前端
cd frontend
flutter build windows
start build\windows\x64\runner\Release\ai_manage_sys.exe
```

## 财务模块

### 支出报销（全员）
- 侧边栏「支出报销」→ 填金额、类别、描述、上传凭证 → 提交报销
- 部门自动带入，只需填金额和类别
- 仅支持报销类型（直接支出仅财务可操作）

### 支出管理（财务审批）
- 财务 Dashboard → 支出管理
- 表格含：金额 / 类别 / 类型 / **部门（彩色标签）** / 描述 / 日期 / 状态 / 操作
- 待审批报销：行末「通过」「驳回」按钮
- 已通过：「支付」按钮
- 直接支出：「编辑」「删除」按钮
- 点击行查看详情弹窗（含部门和关联预算信息）
- 审批通过后系统自动按 部门+类别+日期 匹配叶子预算设 `budget_id`

### 票据管理（发票）
- 表格：编号 / 金额+收款进度条 / 到期日 / 状态彩色标签 / 操作
- 非已收款发票：行末「收款」按钮
- 销售方/购买方详情在点击行弹窗中查看
- 创建发票支持关联预算
- 支持收款记录（银行转账/支票/现金/其他）

### 预算管理
- 树形结构：总预算 → 季度预算 → 部门预算 → 分类项(BudgetItem)
- 菜单上下文：根 → 添加季度预算 / 季度 → 添加Q{n}部门预算 / 部门 → 添加分类预算
- 子预算总额不能超过父预算
- used_amount 自底向上传导
- 堆叠进度条：各分类按类别颜色显示，棋盘格=已支出，绿色底=未分配

### Dashboard
- 预算使用情况：只显示当年顶层预算，精简单色进度条
- 部门颜色管理：快捷操作 → 部门颜色（横向滚动选色，点选即保存）

## 部门颜色
- 财务 Dashboard → 部门颜色 → 每个部门可选 12 色
- 支出列表部门列使用对应颜色标签

## E2E 测试

```bash
cd backend
python -m pytest tests/test_budget_e2e.py -v
```

## DB 迁移历史

```bash
# 添加 budget_id 列
docker exec ai_manage_sys-postgres-1 psql -U ai_manage -d ai_manage -c "
  ALTER TABLE expenses ADD COLUMN IF NOT EXISTS budget_id UUID REFERENCES budgets(id);
  ALTER TABLE settlements ADD COLUMN IF NOT EXISTS budget_id UUID REFERENCES budgets(id);
  ALTER TABLE invoices ADD COLUMN IF NOT EXISTS budget_id UUID REFERENCES budgets(id);
"

# 添加部门颜色列
docker exec ai_manage_sys-postgres-1 psql -U ai_manage -d ai_manage -c "
  ALTER TABLE departments ADD COLUMN IF NOT EXISTS color VARCHAR(32) DEFAULT '#2196F3';
"
```
