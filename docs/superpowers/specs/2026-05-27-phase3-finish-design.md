# Phase 3 收尾设计文档

## 目标

补齐市场部 + 招投标模块的 6 个前端缺失页面 + 1 个后端增强，完成阶段三所有功能。

## 当前状态

- 后端：17 模型 + 34 端点全部完成，E2E 54/54 通过
- 前端：13 页面完成，6 页面缺失
- API 全部就绪，前端直接对接

## 执行顺序

```
Step 1: 迭代3.1 收尾 — ChurnConfig + DemandPrediction (2 pages, simple)
Step 2: 迭代3.2 收尾 — BriefPreview (1 page, simple)
Step 3: 迭代3.3 收尾 — ContractGenerate + ContractDetail + ContractDiff (3 pages, medium)
Step 4: 后端增强 — Knowledge QA history support (small)
Step 5: 验证 — manual smoke + E2E regression
```

---

## Step 1: 迭代3.1 收尾

### ChurnConfigPage (`marketing_churn_config_page.dart`)

- **入口**: CustomerDetailPage 内 "流失预警配置" 按钮 → Navigator.push
- **UI**: Scaffold + AppBar("流失预警配置") + Form
  - 不活跃天数阈值 (TextField, number input)
  - 低满意度阈值 (Slider, 1-100)
  - 自动通知开关 (Switch)
  - 保存按钮 (ElevatedButton)
- **数据流**: initState GET `/marketing/churn-config` → 填充表单 → 保存 PUT `/marketing/churn-config`
- **状态**: loading / error / form
- **预估**: ~100 行

### DemandPredictionPage (`marketing_demand_prediction_page.dart`)

- **入口**: CustomerDetailPage 内 "需求预测" 按钮 → Navigator.push
- **UI**: Scaffold + AppBar("需求预测") + body
  - loading: CircularProgressIndicator + "AI 分析中..."
  - done: SingleChildScrollView + HTML 渲染（复用 preview_page pattern）
  - error: 错误提示
- **数据流**: initState POST `/marketing/customers/{id}/predict-demand` (timeout 120s) → 展示 content_html
- **状态**: loading / done / error
- **预估**: ~90 行

---

## Step 2: 迭代3.2 收尾

### BriefPreviewPage (`marketing_brief_preview_page.dart`)

- **入口**: ProjectTimelineTab 内项目卡片 "生成简报" 按钮 → Navigator.push
- **UI**: Scaffold + AppBar(项目名 + "简报") + body
  - loading: "AI 生成简报中..."
  - done: HTML 渲染
  - 底部: "以上内容由 AI 生成，仅供参考"
- **数据流**: initState POST `/marketing/projects/{id}/brief` (timeout 120s) → 展示 content_html
- **状态**: loading / done / error
- **预估**: ~80 行

---

## Step 3: 迭代3.3 收尾

### ContractGeneratePage (`bidding_contract_generate_page.dart`)

- **入口**: ContractTab FAB "+" → Navigator.push
- **UI**: Scaffold + AppBar("生成合同") + Form
  - 模板下拉 (DropdownButtonFormField, GET `/bidding/templates` 填充)
  - 标题 (TextField)
  - 对方名称 (TextField)
  - 签署日期 (DatePicker)
  - 到期日 (DatePicker)
  - 生成按钮 → POST `/bidding/contracts/generate` (timeout 120s) → 成功跳转 ContractDetailPage
- **状态**: loading / form / generating
- **预估**: ~150 行

### ContractDetailPage (`bidding_contract_detail_page.dart`)

- **入口**: ContractTab 合同卡片点击 → Navigator.push
- **UI**: Scaffold + AppBar(合同标题) + TabBar(内容 | 版本历史)
  - Tab 0 "合同内容": HTML 渲染
  - Tab 1 "版本历史": ListView of version cards (版本号 / 变更摘要 / 创建时间)
  - 版本卡片点击 → "对比当前版本" 按钮 → Navigator.push ContractDiffView
- **数据流**: initState GET `/bidding/contracts/{id}` + GET `/bidding/contracts/{id}/versions`
- **状态**: loading / done / error
- **预估**: ~200 行

### ContractDiffView (`bidding_contract_diff_view.dart`)

- **入口**: ContractDetailPage 版本历史 Tab → "对比版本" 按钮
- **参数**: contractId, version list
- **UI**: 
  - PC (width > 600): Row([v1下拉, v2下拉, "对比"按钮]) + 下方分屏 diff（左旧右新，+/- 着色）
  - Mobile: Column([v1/v2下拉 + 按钮]) + 下方内联 diff
- **数据流**: 选择 v1/v2 → GET `/bidding/contracts/{id}/diff?v1=N&v2=M` → 解析 unified diff text → 渲染
- **Diff 渲染**: 解析 `@@ -a,b +c,d @@` 格式，绿色背景 + 行，红色背景 - 行
- **预估**: ~180 行

---

## Step 4: 后端增强

### Knowledge QA History (`backend/app/api/marketing.py`)

**KnowledgeQARequest 修改：**
```python
class KnowledgeQARequest(BaseModel):
    question: str
    history: list[dict] = []  # 新增: [{role: "user"|"assistant", content: "..."}]
    top_k: int = 5
```

**`/knowledge/qa` 端点修改：**
1. 若 `history` 非空，拼接到 system prompt 中作为对话上下文
2. 搜索时用当前问题 + 最近一条 AI 回复拼接增强搜索词
3. 返回结果 `sources` 格式增强为 `[{id, title, content_preview}]`

**预估**: ~20 行改动

---

## Step 5: 验证

1. 静态分析: `flutter analyze` 0 issues
2. E2E 回归: `test_file/test_e2e_phase3.py` 全部通过
3. 手动冒烟:
   - 客户详情 → 流失配置 → 需求预测
   - 项目跟进 → 生成简报
   - 合同中心 → 生成合同 → 查看详情 → 版本对比
   - 知识库 QA → 多轮对话

## 关键文件

| 文件 | 操作 |
|------|------|
| `frontend/lib/pages/marketing/marketing_churn_config_page.dart` | 新建 |
| `frontend/lib/pages/marketing/marketing_demand_prediction_page.dart` | 新建 |
| `frontend/lib/pages/marketing/marketing_customer_detail_page.dart` | 修改（加入口按钮） |
| `frontend/lib/pages/marketing/marketing_brief_preview_page.dart` | 新建 |
| `frontend/lib/pages/marketing/marketing_project_timeline_tab.dart` | 修改（加"生成简报"按钮） |
| `frontend/lib/pages/bidding/bidding_contract_generate_page.dart` | 新建 |
| `frontend/lib/pages/bidding/bidding_contract_detail_page.dart` | 新建 |
| `frontend/lib/pages/bidding/bidding_contract_diff_view.dart` | 新建 |
| `frontend/lib/pages/bidding/bidding_contract_tab.dart` | 修改（加 FAB + 卡片点击跳转） |
| `backend/app/api/marketing.py` | 修改 KnowledgeQARequest + /knowledge/qa |
