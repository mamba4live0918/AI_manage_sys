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
const _statusColor = {0: AppTheme.green, 1: AppTheme.accent, 2: Colors.grey};
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

// ─── Shared card decoration helpers ───

BoxDecoration _sectionDecoration(bool isDark) => BoxDecoration(
  borderRadius: BorderRadius.circular(12),
  color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
  border: isDark ? Border.all(color: AppTheme.darkElevated, width: 0.5) : null,
  boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 2))],
);

class HrDashboardPage extends ConsumerStatefulWidget {
  const HrDashboardPage({super.key});
  @override
  ConsumerState<HrDashboardPage> createState() => _HrDashboardPageState();
}

class _HrDashboardPageState extends ConsumerState<HrDashboardPage> {
  int _activeView = 0;

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

    if (_activeView == 1) return HrEmployeeListPage(onBack: () => setState(() => _activeView = 0));
    if (_activeView == 2) return HrResumePage(onBack: () => setState(() => _activeView = 0));
    if (_activeView == 3) return HrApprovalPage(onBack: () => setState(() => _activeView = 0));
    if (_activeView == 4) return HrInterviewPage(onBack: () => setState(() => _activeView = 0));

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
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final wide = constraints.maxWidth >= 900;
          final pad = wide ? 24.0 : 12.0;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(pad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: Row(children: [
                  Text('首页', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: Colors.grey))),
                  Text('HR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                ]),
              ),
              _KpiCards(data: data, isDark: isDark),
              const SizedBox(height: 20),
              _ChartsRow(data: data, isDark: isDark),
              const SizedBox(height: 20),
              _ApprovalOverview(data: data, isDark: isDark),
              const SizedBox(height: 20),
              _QuickActions(onSelect: (i) => setState(() => _activeView = i)),
              const SizedBox(height: 20),
              _RecentActivities(data: data, isDark: isDark),
              const SizedBox(height: 20),
              _UpcomingInterviews(data: data, isDark: isDark),
              const SizedBox(height: 80),
            ]),
          );
        },
      ),
    );
  }
}

// ─── KPI Cards ───

class _KpiCards extends StatelessWidget {
  final HrDashboardData data;
  final bool isDark;
  const _KpiCards({required this.data, required this.isDark});

  static const _kpiDefs = [
    ('在职员工', AppTheme.green),
    ('待审简历', AppTheme.pink),
    ('待审批', AppTheme.orange),
    ('今日面试', AppTheme.accent),
  ];

  @override
  Widget build(BuildContext context) {
    final values = [
      '${data.totalEmployees}',
      '${data.pendingResumes}',
      '${data.pendingApprovals}',
      '${data.todayInterviews}',
    ];
    final subs = [
      '+${data.newHiresThisMonth} 本月入职',
      '${data.newResumesToday} 份新投递',
      '${data.approvalsByType.fold<int>(0, (s, t) => s + t.count)} 条总计',
      '本周 ${data.weekInterviews} 场',
    ];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return Row(children: List.generate(4, (i) => Expanded(
            child: Container(
              margin: EdgeInsets.only(left: i > 0 ? 6 : 0, right: i < 3 ? 6 : 0),
              child: _kpiCardWide(_kpiDefs[i].$1, values[i], subs[i], _kpiDefs[i].$2),
            ),
          )));
        }
        // 2x2 grid on narrow
        return Column(children: [
          for (var row = 0; row < 2; row++)
            Padding(
              padding: EdgeInsets.only(top: row > 0 ? 8 : 0),
              child: Row(children: [
                for (var col = 0; col < 2; col++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(left: col > 0 ? 4 : 0, right: col == 0 ? 4 : 0),
                      child: _kpiCardNarrow(_kpiDefs[row * 2 + col].$1, values[row * 2 + col], subs[row * 2 + col], _kpiDefs[row * 2 + col].$2),
                    ),
                  ),
              ]),
            ),
        ]);
      },
    );
  }

  Widget _kpiCardWide(String label, String value, String sub, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
        const SizedBox(height: 4),
        Text(sub, style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
      ]),
    );
  }

  Widget _kpiCardNarrow(String label, String value, String sub, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: accent)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
        ]),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
      ]),
    );
  }
}

// ─── Charts ───

class _ChartsRow extends StatelessWidget {
  final HrDashboardData data;
  final bool isDark;
  const _ChartsRow({required this.data, required this.isDark});

  static const _pieColors = [AppTheme.accent, AppTheme.pink, AppTheme.orange, AppTheme.green, AppTheme.purple, AppTheme.teal];

  Widget _buildDeptChart(ThemeData theme, bool narrow) {
    final deptTotal = data.employeesByDepartment.fold<int>(0, (s, d) => s + d.count);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('部门人员分布', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        SizedBox(
          height: narrow ? 160 : 205,
          child: Row(children: [
            Expanded(
              flex: 2,
              child: RepaintBoundary(
                child: PieChart(
                  PieChartData(
                    sections: data.employeesByDepartment.asMap().entries.map((e) {
                      final color = _pieColors[e.key % _pieColors.length];
                      final pct = deptTotal > 0 ? e.value.count / deptTotal : 0.0;
                      return PieChartSectionData(
                        value: e.value.count.toDouble(),
                        color: color,
                        title: pct > 0.08 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
                        radius: narrow ? 38 : 50,
                        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: narrow ? 22 : 28,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: data.employeesByDepartment.asMap().entries.map((e) {
                  final color = _pieColors[e.key % _pieColors.length];
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: narrow ? 1 : 2),
                    child: Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.value.department, style: TextStyle(fontSize: narrow ? 11 : 12, color: isDark ? Colors.white70 : Colors.black87))),
                      Text('${e.value.count}', style: TextStyle(fontSize: narrow ? 11 : 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildStatusChart(ThemeData theme, bool narrow) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('员工状态', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        SizedBox(
          height: narrow ? 160 : 205,
          child: Row(children: [
            Expanded(
              flex: 2,
              child: RepaintBoundary(
                child: PieChart(
                  PieChartData(
                    sections: data.employeesByStatus.asMap().entries.map((e) {
                      final color = _statusColor[e.key] ?? AppTheme.accent;
                      final total = data.employeesByStatus.fold<int>(0, (s, st) => s + st.count);
                      final pct = total > 0 ? e.value.count / total : 0.0;
                      return PieChartSectionData(
                        value: e.value.count.toDouble(),
                        color: color,
                        title: pct > 0.1 ? '${(pct * 100).toStringAsFixed(0)}%' : '',
                        radius: narrow ? 30 : 40,
                        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      );
                    }).toList(),
                    sectionsSpace: 2,
                    centerSpaceRadius: narrow ? 18 : 22,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: data.employeesByStatus.asMap().entries.map((e) {
                  final color = _statusColor[e.key] ?? AppTheme.accent;
                  final label = _statusLabel[e.value.status] ?? e.value.status;
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: narrow ? 1 : 2),
                    child: Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                      const SizedBox(width: 6),
                      Text(label, style: TextStyle(fontSize: narrow ? 11 : 12, color: isDark ? Colors.white70 : Colors.black87)),
                      const Spacer(),
                      Text('${e.value.count}', style: TextStyle(fontSize: narrow ? 11 : 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildDeptChart(theme, false)),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _buildStatusChart(theme, false)),
            ],
          );
        }
        return Column(children: [
          _buildDeptChart(theme, true),
          const SizedBox(height: 12),
          _buildStatusChart(theme, true),
        ]);
      },
    );
  }
}

// ─── Approval Overview ───

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
      decoration: _sectionDecoration(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('审批概览', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        ...data.approvalsByType.map((t) {
          final label = {'leave': '请假', 'expense': '报销', 'regularization': '转正'}[t.type] ?? t.type;
          final colors = {'leave': AppTheme.orange, 'expense': AppTheme.accent, 'regularization': AppTheme.green};
          final color = colors[t.type] ?? AppTheme.accent;
          final pct = total > 0 ? t.count / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black87)),
                const Spacer(),
                Text('${t.count}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
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

// ─── Quick Actions ───

class _QuickActions extends StatelessWidget {
  final void Function(int viewIndex) onSelect;
  const _QuickActions({required this.onSelect});

  static const _actions = [
    ('员工管理', Icons.people_rounded, AppTheme.accent),
    ('简历管理', Icons.article_rounded, AppTheme.pink),
    ('审批管理', Icons.fact_check_rounded, AppTheme.orange),
    ('面试安排', Icons.event_available_rounded, AppTheme.green),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text('快捷操作', style: theme.textTheme.titleMedium),
      ),
      LayoutBuilder(
        builder: (ctx, constraints) {
          final wide = constraints.maxWidth >= 600;
          if (wide) {
            return Row(
              children: _actions.asMap().entries.map((e) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: e.key > 0 ? 6 : 0, right: e.key < 3 ? 6 : 0),
                  child: _actionCard(e.value.$1, e.value.$2, e.value.$3, () => onSelect(e.key + 1), isDark),
                ),
              )).toList(),
            );
          }
          return Column(children: [
            for (var row = 0; row < 2; row++)
              Padding(
                padding: EdgeInsets.only(top: row > 0 ? 8 : 0),
                child: Row(children: [
                  for (var col = 0; col < 2; col++)
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.only(left: col > 0 ? 4 : 0, right: col == 0 ? 4 : 0),
                        child: _actionCard(_actions[row * 2 + col].$1, _actions[row * 2 + col].$2, _actions[row * 2 + col].$3, () => onSelect(row * 2 + col + 1), isDark),
                      ),
                    ),
                ]),
              ),
          ]);
        },
      ),
    ]);
  }

  Widget _actionCard(String label, IconData icon, Color color, VoidCallback onTap, bool isDark) {
    return Material(
      color: color.withAlpha(isDark ? 18 : 15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withAlpha(25)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }
}

// ─── Recent Activities ───

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
      decoration: _sectionDecoration(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('最近动态', style: theme.textTheme.titleMedium),
        const SizedBox(height: 14),
        ...data.recentActivities.take(8).map((a) {
          final icon = _actionIcon[a.action] ?? Icons.circle;
          final label = _actionLabel[a.action] ?? a.action;
          Color iconColor;
          if (a.action.contains('approved') || a.action.contains('create') || a.action.contains('upload')) {
            iconColor = AppTheme.green;
          } else if (a.action.contains('rejected') || a.action.contains('delete')) {
            iconColor = AppTheme.red;
          } else if (a.action.contains('update')) {
            iconColor = AppTheme.accent;
          } else {
            iconColor = AppTheme.orange;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: iconColor.withAlpha(isDark ? 20 : 15)),
                child: Icon(icon, size: 14, color: iconColor),
              ),
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
              Text(_timeAgo(a.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          );
        }),
      ]),
    );
  }
}

// ─── Upcoming Interviews ───

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
      decoration: _sectionDecoration(isDark),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('近期面试', style: theme.textTheme.titleMedium),
        const SizedBox(height: 14),
        ...data.upcomingInterviews.map((i) {
          String dateStr = '';
          if (i.scheduledAt != null) {
            final dt = DateTime.tryParse(i.scheduledAt!);
            if (dt != null) dateStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: AppTheme.accent.withAlpha(isDark ? 20 : 15)),
                child: const Icon(Icons.person_outline, color: AppTheme.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.candidateName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(i.position, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                ]),
              ),
              if (dateStr.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppTheme.accent.withAlpha(isDark ? 20 : 15)),
                  child: Text(dateStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent)),
                ),
            ]),
          );
        }),
      ]),
    );
  }
}
