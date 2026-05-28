# HR Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace HR TabBar page with a full dashboard (KPI cards, charts, quick actions, recent activity) + standalone sub-pages.

**Architecture:** New `/hr/dashboard` backend endpoint aggregates data from users/resumes/approvals/interviews/audit_logs. Frontend uses Riverpod provider + fl_chart PieChart, matching PM overview tab patterns. Quick actions navigate to standalone Scaffold pages wrapping existing tab widgets.

**Tech Stack:** FastAPI + SQLAlchemy (backend), Flutter + Riverpod + fl_chart (frontend)

---

### File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `backend/app/api/hr.py` | Modify | Add `GET /hr/dashboard` endpoint |
| `frontend/lib/models/hr_dashboard.dart` | Create | Dashboard data model + fromJson |
| `frontend/lib/providers/hr_dashboard_provider.dart` | Create | Riverpod StateNotifier for dashboard state |
| `frontend/lib/pages/hr/hr_dashboard_page.dart` | Rewrite | Full dashboard UI (no TabBar) |
| `frontend/lib/pages/hr/hr_employee_list_page.dart` | Create | Standalone employee mgmt page |
| `frontend/lib/pages/hr/hr_resume_page.dart` | Create | Standalone resume page |
| `frontend/lib/pages/hr/hr_approval_page.dart` | Create | Standalone approval page |
| `frontend/lib/pages/hr/hr_interview_page.dart` | Create | Standalone interview page |

---

### Task 1: Backend — Add `GET /hr/dashboard` endpoint

**Files:**
- Modify: `backend/app/api/hr.py`

- [ ] **Step 1: Add dashboard endpoint to hr.py**

Append to `backend/app/api/hr.py`:

```python
# ── Dashboard ──

@router.get("/dashboard")
async def get_hr_dashboard(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Aggregated HR dashboard data."""
    if user.role not in ("admin", "hr"):
        raise HTTPException(403, "仅HR/管理员可访问")

    dept_filter = []
    if user.role != "admin" and user.department_id:
        dept_filter.append(User.department_id == user.department_id)

    # Employee stats
    emp_base = select(User).where(User.role == "general")
    for f in dept_filter:
        emp_base = emp_base.where(f)

    emp_result = await db.execute(emp_base)
    employees = emp_result.scalars().all()
    total = len(employees)
    active = sum(1 for e in employees if e.emp_status == "active")
    probation = sum(1 for e in employees if e.emp_status == "probation")
    resigned = sum(1 for e in employees if e.emp_status == "resigned")
    this_month = sum(1 for e in employees if e.hire_date and e.hire_date.month == _now().month and e.hire_date.year == _now().year)

    dept_counts: dict[str, int] = {}
    for e in employees:
        d = e.department or "未分配"
        dept_counts[d] = dept_counts.get(d, 0) + 1
    employees_by_department = [{"department": k, "count": v} for k, v in dept_counts.items()]

    employees_by_status = [
        {"status": "active", "count": active},
        {"status": "probation", "count": probation},
        {"status": "resigned", "count": resigned},
    ]

    # Resume stats
    resume_base = select(Resume)
    if user.role != "admin" and user.department_id:
        resume_base = resume_base.where(Resume.department_id == user.department_id)
    resume_result = await db.execute(resume_base)
    resumes = resume_result.scalars().all()

    pending_resumes = sum(1 for r in resumes if r.status == "new")
    today_resumes = sum(1 for r in resumes if r.created_at and r.created_at.date() == _now().date())

    resume_status_counts: dict[str, int] = {}
    for r in resumes:
        s = r.status or "new"
        resume_status_counts[s] = resume_status_counts.get(s, 0) + 1
    resumes_by_status = [{"status": k, "count": v} for k, v in resume_status_counts.items()]

    # Approval stats
    approval_base = select(Approval)
    if user.role != "admin" and user.department_id:
        approval_base = approval_base.where(Approval.department_id == user.department_id)
    approval_result = await db.execute(approval_base)
    approvals = approval_result.scalars().all()

    pending_approvals = sum(1 for a in approvals if a.status == "pending")
    approval_type_counts: dict[str, int] = {}
    for a in approvals:
        approval_type_counts[a.approval_type] = approval_type_counts.get(a.approval_type, 0) + 1
    approvals_by_type = [{"type": k, "count": v} for k, v in approval_type_counts.items()]

    # Interview stats
    interview_base = select(Interview)
    if user.role != "admin" and user.department_id:
        interview_base = interview_base.where(Interview.department_id == user.department_id)
    interview_result = await db.execute(interview_base)
    interviews = interview_result.scalars().all()

    today_date = _now().date()
    today_interviews = sum(1 for i in interviews if i.scheduled_at and i.scheduled_at.date() == today_date)
    week_start = today_date - __import__("datetime").timedelta(days=today_date.weekday())
    week_end = week_start + __import__("datetime").timedelta(days=6)
    week_interviews = sum(1 for i in interviews if i.scheduled_at and week_start <= i.scheduled_at.date() <= week_end)

    upcoming = sorted(
        [i for i in interviews if i.scheduled_at and i.scheduled_at >= _now()],
        key=lambda x: x.scheduled_at,
    )[:5]
    upcoming_interviews = [_interview_row(i) for i in upcoming]

    # Recent HR activities
    hr_actions = [
        "resume_create", "resume_upload", "resume_match", "resume_update", "resume_delete",
        "approval_create", "approval_approved", "approval_rejected",
        "approval_step_approved", "approval_step_rejected",
        "interview_create", "interview_update", "interview_delete",
        "employee_update",
    ]
    audit_query = select(AuditLog).where(AuditLog.action.in_(hr_actions)).order_by(AuditLog.created_at.desc()).limit(20)
    if user.role != "admin" and user.department_id:
        audit_query = audit_query.where(AuditLog.user_id.in_(
            select(User.id).where(User.department_id == user.department_id)
        ))
    audit_result = await db.execute(audit_query)
    recent_activities = []
    for a in audit_result.scalars().all():
        recent_activities.append({
            "id": str(a.id),
            "username": a.username,
            "action": a.action,
            "resource_type": a.resource_type,
            "resource_name": a.resource_name,
            "detail": a.detail,
            "created_at": a.created_at.isoformat() if a.created_at else None,
        })

    return {
        "total_employees": total,
        "active_employees": active,
        "new_hires_this_month": this_month,
        "employees_by_department": employees_by_department,
        "employees_by_status": employees_by_status,
        "pending_resumes": pending_resumes,
        "new_resumes_today": today_resumes,
        "resumes_by_status": resumes_by_status,
        "pending_approvals": pending_approvals,
        "approvals_by_type": approvals_by_type,
        "today_interviews": today_interviews,
        "week_interviews": week_interviews,
        "upcoming_interviews": upcoming_interviews,
        "recent_activities": recent_activities,
    }
```

Note: Add `from app.models import AuditLog` if not already imported (check existing imports at top of file — AuditLog may need to be added to the import line).

- [ ] **Step 2: Verify the endpoint returns 200**

```bash
curl -X GET http://localhost:8001/hr/dashboard -H "Authorization: Bearer <token>"
```

- [ ] **Step 3: Commit**

```bash
git add backend/app/api/hr.py
git commit -m "feat: add GET /hr/dashboard aggregated endpoint"
```

---

### Task 2: Frontend — Dashboard data model

**Files:**
- Create: `frontend/lib/models/hr_dashboard.dart`

- [ ] **Step 1: Create the model**

```dart
class HrDashboardData {
  final int totalEmployees;
  final int activeEmployees;
  final int newHiresThisMonth;
  final List<DeptCount> employeesByDepartment;
  final List<StatusCount> employeesByStatus;
  final int pendingResumes;
  final int newResumesToday;
  final List<StatusCount> resumesByStatus;
  final int pendingApprovals;
  final List<TypeCount> approvalsByType;
  final int todayInterviews;
  final int weekInterviews;
  final List<UpcomingInterview> upcomingInterviews;
  final List<Activity> recentActivities;

  HrDashboardData({
    required this.totalEmployees,
    required this.activeEmployees,
    required this.newHiresThisMonth,
    required this.employeesByDepartment,
    required this.employeesByStatus,
    required this.pendingResumes,
    required this.newResumesToday,
    required this.resumesByStatus,
    required this.pendingApprovals,
    required this.approvalsByType,
    required this.todayInterviews,
    required this.weekInterviews,
    required this.upcomingInterviews,
    required this.recentActivities,
  });

  factory HrDashboardData.fromJson(Map<String, dynamic> json) {
    return HrDashboardData(
      totalEmployees: json['total_employees'] ?? 0,
      activeEmployees: json['active_employees'] ?? 0,
      newHiresThisMonth: json['new_hires_this_month'] ?? 0,
      employeesByDepartment: (json['employees_by_department'] as List<dynamic>?)
              ?.map((e) => DeptCount.fromJson(e))
              .toList() ?? [],
      employeesByStatus: (json['employees_by_status'] as List<dynamic>?)
              ?.map((e) => StatusCount.fromJson(e))
              .toList() ?? [],
      pendingResumes: json['pending_resumes'] ?? 0,
      newResumesToday: json['new_resumes_today'] ?? 0,
      resumesByStatus: (json['resumes_by_status'] as List<dynamic>?)
              ?.map((e) => StatusCount.fromJson(e))
              .toList() ?? [],
      pendingApprovals: json['pending_approvals'] ?? 0,
      approvalsByType: (json['approvals_by_type'] as List<dynamic>?)
              ?.map((e) => TypeCount.fromJson(e))
              .toList() ?? [],
      todayInterviews: json['today_interviews'] ?? 0,
      weekInterviews: json['week_interviews'] ?? 0,
      upcomingInterviews: (json['upcoming_interviews'] as List<dynamic>?)
              ?.map((e) => UpcomingInterview.fromJson(e))
              .toList() ?? [],
      recentActivities: (json['recent_activities'] as List<dynamic>?)
              ?.map((e) => Activity.fromJson(e))
              .toList() ?? [],
    );
  }
}

class DeptCount {
  final String department;
  final int count;
  DeptCount({required this.department, required this.count});
  factory DeptCount.fromJson(Map<String, dynamic> json) =>
      DeptCount(department: json['department'] ?? '', count: json['count'] ?? 0);
}

class StatusCount {
  final String status;
  final int count;
  StatusCount({required this.status, required this.count});
  factory StatusCount.fromJson(Map<String, dynamic> json) =>
      StatusCount(status: json['status'] ?? '', count: json['count'] ?? 0);
}

class TypeCount {
  final String type;
  final int count;
  TypeCount({required this.type, required this.count});
  factory TypeCount.fromJson(Map<String, dynamic> json) =>
      TypeCount(type: json['type'] ?? '', count: json['count'] ?? 0);
}

class UpcomingInterview {
  final String candidateName;
  final String position;
  final String? scheduledAt;
  UpcomingInterview({required this.candidateName, required this.position, this.scheduledAt});
  factory UpcomingInterview.fromJson(Map<String, dynamic> json) =>
      UpcomingInterview(
        candidateName: json['candidate_name'] ?? '',
        position: json['position'] ?? '',
        scheduledAt: json['scheduled_at'],
      );
}

class Activity {
  final String username;
  final String action;
  final String resourceName;
  final String? createdAt;
  Activity({required this.username, required this.action, required this.resourceName, this.createdAt});
  factory Activity.fromJson(Map<String, dynamic> json) =>
      Activity(
        username: json['username'] ?? '',
        action: json['action'] ?? '',
        resourceName: json['resource_name'] ?? '',
        createdAt: json['created_at'],
      );
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/models/hr_dashboard.dart
git commit -m "feat: add HR dashboard data model"
```

---

### Task 3: Frontend — Dashboard provider

**Files:**
- Create: `frontend/lib/providers/hr_dashboard_provider.dart`

- [ ] **Step 1: Create the provider**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hr_dashboard.dart';
import '../services/api_client.dart';

class HrDashboardState {
  final HrDashboardData? data;
  final bool loading;
  final String? error;

  HrDashboardState({this.data, this.loading = false, this.error});

  HrDashboardState copyWith({HrDashboardData? data, bool? loading, String? error}) {
    return HrDashboardState(
      data: data ?? this.data,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class HrDashboardNotifier extends StateNotifier<HrDashboardState> {
  final ApiClient _api = ApiClient();

  HrDashboardNotifier() : super(HrDashboardState(loading: true));

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.dio.get('/hr/dashboard');
      final data = HrDashboardData.fromJson(resp.data);
      state = state.copyWith(data: data, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final hrDashboardProvider = StateNotifierProvider<HrDashboardNotifier, HrDashboardState>((ref) {
  return HrDashboardNotifier();
});
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/providers/hr_dashboard_provider.dart
git commit -m "feat: add HR dashboard Riverpod provider"
```

---

### Task 4: Frontend — Rewrite dashboard page

**Files:**
- Modify: `frontend/lib/pages/hr/hr_dashboard_page.dart`

- [ ] **Step 1: Replace entire file with dashboard implementation**

Replace the entire content of `hr_dashboard_page.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/hr_dashboard_provider.dart';
import '../../widgets/watermark.dart';
import '../../models/hr_dashboard.dart';
import 'hr_employee_list_page.dart';
import 'hr_resume_page.dart';
import 'hr_approval_page.dart';
import 'hr_interview_page.dart';

const _statusLabel = {'active': '在职', 'probation': '试用期', 'resigned': '离职'};
const _statusColor = {0: AppTheme.green, 1: AppTheme.blue, 2: Colors.grey};
const _actionLabel = {
  'resume_create': '上传简历', 'resume_upload': '上传简历',
  'resume_match': '评估简历', 'resume_update': '更新简历',
  'approval_create': '提交审批', 'approval_approved': '审批通过',
  'approval_rejected': '审批驳回', 'approval_step_approved': '审批步骤通过',
  'approval_step_rejected': '审批步骤驳回',
  'interview_create': '安排面试', 'interview_update': '更新面试',
  'employee_update': '更新员工信息',
};
const _actionIcon = {
  'resume_create': Icons.upload_file, 'resume_upload': Icons.upload_file,
  'resume_match': Icons.analytics, 'resume_update': Icons.edit,
  'approval_create': Icons.send, 'approval_approved': Icons.check_circle,
  'approval_rejected': Icons.cancel, 'approval_step_approved': Icons.check_circle,
  'approval_step_rejected': Icons.cancel,
  'interview_create': Icons.calendar_today, 'interview_update': Icons.edit_calendar,
  'employee_update': Icons.person,
};

class HrDashboardPage extends ConsumerStatefulWidget {
  const HrDashboardPage({super.key});
  @override
  ConsumerState<HrDashboardPage> createState() => _HrDashboardPageState();
}

class _HrDashboardPageState extends ConsumerState<HrDashboardPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(hrDashboardProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final state = ref.watch(hrDashboardProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('HR')),
        body: _buildBody(state, isDark),
      ),
    );
  }

  Widget _buildBody(HrDashboardState state, bool isDark) {
    if (state.loading && state.data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.data == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('加载失败', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => ref.read(hrDashboardProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ]),
      );
    }
    final data = state.data!;
    return RefreshIndicator(
      onRefresh: () => ref.read(hrDashboardProvider.notifier).load(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _KpiCards(data: data, isDark: isDark),
          const SizedBox(height: 20),
          _ChartsRow(data: data, isDark: isDark),
          const SizedBox(height: 20),
          _ApprovalOverview(data: data, isDark: isDark),
          const SizedBox(height: 20),
          _QuickActions(),
          const SizedBox(height: 20),
          _RecentActivities(data: data, isDark: isDark),
          const SizedBox(height: 20),
          _UpcomingInterviews(data: data, isDark: isDark),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

class _KpiCards extends StatelessWidget {
  final HrDashboardData data;
  final bool isDark;
  const _KpiCards({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        '在职员工',
        '${data.totalEmployees}',
        '+${data.newHiresThisMonth} 本月入职',
        [const Color(0xFF667eea), const Color(0xFF764ba2)],
        [const Color(0xFF667eea).withAlpha(60), const Color(0xFF764ba2).withAlpha(70)],
      ),
      (
        '待审简历',
        '${data.pendingResumes}',
        '${data.newResumesToday} 份新投递',
        [const Color(0xFFf093fb), const Color(0xFFf5576c)],
        [const Color(0xFFf5576c).withAlpha(60), const Color(0xFFf093fb).withAlpha(50)],
      ),
      (
        '待审批',
        '${data.pendingApprovals}',
        '${data.approvalsByType.fold<int>(0, (s, t) => s + t.count)} 条总计',
        [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
        [const Color(0xFF4facfe).withAlpha(60), const Color(0xFF00f2fe).withAlpha(50)],
      ),
      (
        '今日面试',
        '${data.todayInterviews}',
        '本周 ${data.weekInterviews} 场',
        [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
        [const Color(0xFF43e97b).withAlpha(50), const Color(0xFF38f9d7).withAlpha(50)],
      ),
    ];

    return Row(
      children: cards.map((c) {
        final (label, value, sub, lightGrad, darkGrad) = c;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: isDark ? darkGrad : lightGrad,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: isDark ? Border.all(color: (lightGrad[0] as Color).withAlpha(40), width: 1) : null,
              boxShadow: isDark ? [] : [BoxShadow(color: (lightGrad[0] as Color).withAlpha(40), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withAlpha(210))),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 4),
                Text(sub, style: TextStyle(fontSize: 11, color: Colors.white.withAlpha(170))),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChartsRow extends StatelessWidget {
  final HrDashboardData data;
  final bool isDark;
  const _ChartsRow({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deptTotal = data.employeesByDepartment.fold<int>(0, (s, d) => s + d.count);
    final pieColors = [AppTheme.blue, AppTheme.pink, AppTheme.orange, AppTheme.green, AppTheme.purple, AppTheme.teal];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              border: isDark ? Border.all(color: AppTheme.darkElevated) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('部门人员分布', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: PieChart(
                      PieChartData(
                        sections: data.employeesByDepartment.asMap().entries.map((e) {
                          final color = pieColors[e.key % pieColors.length];
                          final pct = deptTotal > 0 ? e.value.count / deptTotal : 0.0;
                          return PieChartSectionData(
                            value: e.value.count.toDouble(),
                            color: color,
                            title: pct > 0.08 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
                            radius: 50,
                            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: data.employeesByDepartment.asMap().entries.map((e) {
                        final color = pieColors[e.key % pieColors.length];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                            const SizedBox(width: 6),
                            Expanded(child: Text(e.value.department, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87))),
                            Text('${e.value.count}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              border: isDark ? Border.all(color: AppTheme.darkElevated) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('员工状态', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: PieChart(
                  PieChartData(
                    sections: data.employeesByStatus.asMap().entries.map((e) {
                      final color = _statusColor[e.key] ?? AppTheme.blue;
                      final total = data.employeesByStatus.fold<int>(0, (s, st) => s + st.count);
                      final pct = total > 0 ? e.value.count / total : 0.0;
                      return PieChartSectionData(
                        value: e.value.count.toDouble(),
                        color: color,
                        title: pct > 0.1 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
                        radius: 45,
                        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: 25,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...data.employeesByStatus.asMap().entries.map((e) {
                final color = _statusColor[e.key] ?? AppTheme.blue;
                final label = _statusLabel[e.value.status] ?? e.value.status;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                    const SizedBox(width: 6),
                    Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
                    const Spacer(),
                    Text('${e.value.count}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                  ]),
                );
              }),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ApprovalOverview extends StatelessWidget {
  final HrDashboardData data;
  final bool isDark;
  const _ApprovalOverview({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = data.approvalsByType.fold<int>(0, (s, t) => s + t.count);
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: isDark ? Border.all(color: AppTheme.darkElevated) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('审批概览', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        ...data.approvalsByType.map((t) {
          final label = {'leave': '请假', 'expense': '报销', 'regularization': '转正'}[t.type] ?? t.type;
          final colors = {'leave': AppTheme.orange, 'expense': AppTheme.blue, 'regularization': AppTheme.green};
          final color = colors[t.type] ?? AppTheme.blue;
          final pct = total > 0 ? t.count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(label, style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                const Spacer(),
                Text('${t.count}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: isDark ? AppTheme.darkElevated : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final actions = [
      ('员工管理', Icons.people_rounded, const Color(0xFF667eea), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrEmployeeListPage()))),
      ('简历管理', Icons.article_rounded, const Color(0xFFf5576c), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrResumePage()))),
      ('审批管理', Icons.fact_check_rounded, const Color(0xFF4facfe), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrApprovalPage()))),
      ('面试安排', Icons.event_available_rounded, const Color(0xFF43e97b), () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HrInterviewPage()))),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text('快捷操作', style: Theme.of(context).textTheme.titleMedium),
      ),
      Row(
        children: actions.map((a) {
          final (label, icon, color, onTap) = a;
          return Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: color.withAlpha(20),
                ),
                child: Column(children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(height: 8),
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

class _RecentActivities extends StatelessWidget {
  final HrDashboardData data;
  final bool isDark;
  const _RecentActivities({required this.data, required this.isDark});

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.recentActivities.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: isDark ? Border.all(color: AppTheme.darkElevated) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('最近动态', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        ...data.recentActivities.take(8).map((a) {
          final icon = _actionIcon[a.action] ?? Icons.circle;
          final label = _actionLabel[a.action] ?? a.action;
          Color iconColor;
          if (a.action.contains('approved') || a.action.contains('create') || a.action.contains('upload')) {
            iconColor = AppTheme.green;
          } else if (a.action.contains('rejected') || a.action.contains('delete')) {
            iconColor = AppTheme.red;
          } else if (a.action.contains('update')) {
            iconColor = AppTheme.blue;
          } else {
            iconColor = AppTheme.orange;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                    children: [
                      TextSpan(text: a.username, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                      TextSpan(text: ' $label'),
                      if (a.resourceName.isNotEmpty) TextSpan(text: ' — ${a.resourceName}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(_timeAgo(a.createdAt), style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          );
        }),
      ]),
    );
  }
}

class _UpcomingInterviews extends StatelessWidget {
  final HrDashboardData data;
  final bool isDark;
  const _UpcomingInterviews({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.upcomingInterviews.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: isDark ? Border.all(color: AppTheme.darkElevated) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('近期面试', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        ...data.upcomingInterviews.map((i) {
          String dateStr = '';
          if (i.scheduledAt != null) {
            final dt = DateTime.tryParse(i.scheduledAt!);
            if (dt != null) dateStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: AppTheme.blue.withAlpha(20)),
                child: const Icon(Icons.person_outline, color: AppTheme.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.candidateName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                  Text(i.position, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                ]),
              ),
              if (dateStr.isNotEmpty)
                Text(dateStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.blue)),
            ]),
          );
        }),
      ]),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add frontend/lib/pages/hr/hr_dashboard_page.dart
git commit -m "feat: rewrite HR page as full dashboard with charts + quick actions"
```

---

### Task 5: Frontend — Create standalone sub-pages (4 files)

**Files:**
- Create: `frontend/lib/pages/hr/hr_employee_list_page.dart`
- Create: `frontend/lib/pages/hr/hr_resume_page.dart`
- Create: `frontend/lib/pages/hr/hr_approval_page.dart`
- Create: `frontend/lib/pages/hr/hr_interview_page.dart`

- [ ] **Step 1: Create hr_employee_list_page.dart**

```dart
import 'package:flutter/material.dart';
import 'hr_user_management_tab.dart';

class HrEmployeeListPage extends StatelessWidget {
  const HrEmployeeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('员工管理')),
      body: const HrUserManagementTab(),
    );
  }
}
```

- [ ] **Step 2: Create hr_resume_page.dart**

```dart
import 'package:flutter/material.dart';
import 'hr_resume_tab.dart';

class HrResumePage extends StatelessWidget {
  const HrResumePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('简历管理')),
      body: const HrResumeTab(),
    );
  }
}
```

- [ ] **Step 3: Create hr_approval_page.dart**

```dart
import 'package:flutter/material.dart';
import 'hr_approval_tab.dart';

class HrApprovalPage extends StatelessWidget {
  const HrApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('审批管理')),
      body: const HrApprovalTab(),
    );
  }
}
```

- [ ] **Step 4: Create hr_interview_page.dart**

```dart
import 'package:flutter/material.dart';
import 'hr_interview_tab.dart';

class HrInterviewPage extends StatelessWidget {
  const HrInterviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('面试安排')),
      body: const HrInterviewTab(),
    );
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add frontend/lib/pages/hr/hr_employee_list_page.dart frontend/lib/pages/hr/hr_resume_page.dart frontend/lib/pages/hr/hr_approval_page.dart frontend/lib/pages/hr/hr_interview_page.dart
git commit -m "feat: add standalone HR sub-pages wrapping existing tabs"
```
