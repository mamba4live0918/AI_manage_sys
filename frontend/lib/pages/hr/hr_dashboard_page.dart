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
              border: isDark ? Border.all(color: lightGrad[0].withAlpha(40), width: 1) : null,
              boxShadow: isDark ? [] : [BoxShadow(color: lightGrad[0].withAlpha(40), blurRadius: 12, offset: const Offset(0, 4))],
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
                height: 205,
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
              Text(_timeAgo(a.createdAt), style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                Text(dateStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.blue)),
            ]),
          );
        }),
      ]),
    );
  }
}
