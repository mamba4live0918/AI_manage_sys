# HR Dashboard Design

## Overview

Replace the current TabBar-based HR page with a full dashboard featuring KPI cards, charts, quick actions, and recent activity. Quick actions navigate to independent sub-pages for each HR function.

## Design Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Layout | Full dashboard, no TabBar | User preference |
| Page structure | SingleChildScrollView with sections | Matches PM overview pattern |
| Navigation | Dashboard → Navigator.push to sub-pages | Clean separation, reusable tab content |
| Charts | fl_chart PieChart | Already in project, matches PM pattern |
| Theme | Material 3 light/dark auto | Matches existing app behavior |

## Backend: `GET /hr/dashboard`

**File:** `backend/app/api/hr.py` (add endpoint)

**Response schema:**
```json
{
  "total_employees": 156,
  "active_employees": 148,
  "new_hires_this_month": 3,
  "employees_by_department": [{"department": "...", "count": N}],
  "employees_by_status": [{"status": "active", "count": N}, ...],
  "pending_resumes": 23,
  "new_resumes_today": 5,
  "resumes_by_status": [{"status": "new", "count": N}, ...],
  "pending_approvals": 8,
  "approvals_by_type": [{"type": "leave", "count": N}, ...],
  "today_interviews": 4,
  "week_interviews": 12,
  "upcoming_interviews": [{...}],
  "recent_activities": [{...}]
}
```

**Data sources:**
- Employees: `users` table (role-based, emp_status/position fields)
- Resumes: `resumes` table (status counts)
- Approvals: `approvals` table (status/type counts)
- Interviews: `interviews` table (today/this_week counts + upcoming list)
- Activities: `audit_logs` table (last 20 HR-related entries)

**Permission:** `require_roles("admin", "hr")`

## Frontend Structure

### Files

| File | Operation | Description |
|------|-----------|-------------|
| `hr_dashboard_page.dart` | Rewrite | Full dashboard, no TabBar |
| `models/hr_dashboard.dart` | New | Dashboard data model + JSON parsing |
| `providers/hr_dashboard_provider.dart` | New | Riverpod StateNotifier for dashboard state |
| `hr_employee_list_page.dart` | New | Standalone employee management page |
| `hr_resume_page.dart` | New | Standalone resume page |
| `hr_approval_page.dart` | New | Standalone approval page |
| `hr_interview_page.dart` | New | Standalone interview page |

### Dashboard Layout (top to bottom)

```
SingleChildScrollView
├── Section 1: KPI Cards Row (4 gradient cards)
│   ├── Card: Total Employees (purple gradient)
│   ├── Card: Pending Resumes (pink gradient)
│   ├── Card: Pending Approvals (blue gradient)
│   └── Card: Today's Interviews (green gradient)
├── Section 2: Charts Row
│   ├── Department Distribution (PieChart + legend)
│   └── Employee Status Distribution (PieChart)
├── Section 3: Approval Overview (progress bars)
├── Section 4: Quick Actions (4 navigation buttons)
├── Section 5: Recent Activities (timeline list)
└── Section 6: Upcoming Interviews (card list)
```

### KPI Card Design

Each card: `Container` with `LinearGradient` background, rounded corners, shadow. Light mode uses full-opacity gradients; dark mode uses semi-transparent gradients with border.

### Sub-pages

Each sub-page is a full `Scaffold` with AppBar + back button. Content reuses logic from existing tab widgets but wrapped in standalone pages. This keeps the dashboard clean while preserving all existing functionality.

## Errors & Edge Cases

- **Dashboard data fetch fails**: Show error state with retry button (match PM pattern)
- **Empty state**: Show 0 values in KPI cards with "暂无数据" labels
- **Permission denied (non-HR user)**: Backend returns 403, frontend redirects
- **Loading state**: `CircularProgressIndicator` center-screen (match existing pattern)

## Out of Scope

- Dashboard card drag-to-rearrange
- Date range filters (use current month/week as default)
- Export/report generation
