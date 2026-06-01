import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _stageNames = {
  'initiation': '启动', 'planning': '规划', 'execution': '执行',
  'monitoring': '监控', 'closure': '收尾',
};

const _stageColors = {
  'initiation': AppTheme.blue,
  'planning': AppTheme.orange,
  'execution': AppTheme.green,
  'monitoring': AppTheme.purple,
  'closure': AppTheme.teal,
};

class PmOverviewTab extends StatefulWidget {
  const PmOverviewTab({super.key});

  @override
  State<PmOverviewTab> createState() => _PmOverviewTabState();
}

class _PmOverviewTabState extends State<PmOverviewTab> {
  final _api = ApiClient();
  Map<String, dynamic>? _stats;
  bool _loading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/pm/stats');
      setState(() {
        _stats = resp.data;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Map<DateTime, List<Map<String, dynamic>>> _eventsByDay() {
    final events = <DateTime, List<Map<String, dynamic>>>{};
    final raw = _stats?['calendar_events'] as List<dynamic>? ?? [];
    for (final e in raw) {
      final dateStr = e['date'] as String?;
      if (dateStr == null) continue;
      final dt = DateTime.tryParse(dateStr);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      events.putIfAbsent(day, () => []).add(Map<String, dynamic>.from(e as Map));
    }
    return events;
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    return _eventsByDay()[normalized] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_stats == null) return const Center(child: Text('加载失败'));

    final totalProjects = _stats!['total_projects'] as int? ?? 0;
    final totalBudget = (_stats!['total_budget'] as num?)?.toDouble() ?? 0;
    final stages = _stats!['stages'] as List<dynamic>? ?? [];
    final projectsBudget = _stats!['projects_budget'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SummaryCards(totalProjects: totalProjects, totalBudget: totalBudget, stages: stages, isDark: isDark),
        const SizedBox(height: 16),
        _StagePieChart(stages: stages, isDark: isDark),
        const SizedBox(height: 16),
        if (projectsBudget.isNotEmpty) ...[
          _BudgetBarChart(projects: projectsBudget, isDark: isDark),
          const SizedBox(height: 16),
        ],
        _ProjectCalendar(
          eventsByDay: _eventsByDay(),
          eventsForDay: _eventsForDay,
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: (selected, focused) => setState(() { _selectedDay = selected; _focusedDay = focused; }),
          onPageChanged: (focused) => setState(() => _focusedDay = focused),
          isDark: isDark,
        ),
        const SizedBox(height: 80),
      ]),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final int totalProjects;
  final double totalBudget;
  final List<dynamic> stages;
  final bool isDark;

  const _SummaryCards({required this.totalProjects, required this.totalBudget, required this.stages, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final activeStages = stages.where((s) => s['stage'] != 'closure').fold<int>(0, (sum, s) => sum + ((s['count'] as int?) ?? 0));

    final cards = [
      ('项目总数', '$totalProjects', Icons.folder_rounded, AppTheme.blue),
      ('总预算', '\$${totalBudget.toStringAsFixed(0)}', Icons.account_balance_wallet_rounded, AppTheme.green),
      ('进行中', '$activeStages', Icons.play_circle_rounded, AppTheme.orange),
    ];

    return Row(
      children: cards.map((c) {
        final (label, value, icon, color) = c;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withAlpha(isDark ? 20 : 15),
            ),
            child: Column(children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: (isDark ? AppTheme.darkText : AppTheme.lightText).withAlpha(150))),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _StagePieChart extends StatelessWidget {
  final List<dynamic> stages;
  final bool isDark;

  const _StagePieChart({required this.stages, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (stages.isEmpty) return const SizedBox.shrink();

    final total = stages.fold<int>(0, (s, e) => s + ((e['count'] as int?) ?? 0));
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('项目阶段分布', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: Row(children: [
            Expanded(
              flex: 3,
              child: PieChart(
                PieChartData(
                  sections: stages.map((s) {
                    final stage = s['stage'] as String? ?? '';
                    final count = (s['count'] as int?) ?? 0;
                    final pct = count / total;
                    final color = _stageColors[stage] ?? AppTheme.blue;
                    return PieChartSectionData(
                      value: count.toDouble(),
                      color: color,
                      title: '${(pct * 100).toStringAsFixed(0)}%',
                      radius: 60,
                      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 30,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: stages.map((s) {
                  final stage = s['stage'] as String? ?? '';
                  final count = s['count'] as int? ?? 0;
                  final color = _stageColors[stage] ?? AppTheme.blue;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_stageNames[stage] ?? stage, style: const TextStyle(fontSize: 13))),
                      Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
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
}

class _BudgetBarChart extends StatelessWidget {
  final List<dynamic> projects;
  final bool isDark;

  const _BudgetBarChart({required this.projects, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxBudget = projects.fold<double>(0, (m, p) => ((p['budget'] as num?)?.toDouble() ?? 0) > m ? ((p['budget'] as num?)?.toDouble() ?? 0) : m);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('项目预算概览', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxBudget * 1.2,
              barGroups: projects.asMap().entries.map((e) {
                final p = e.value;
                final budget = (p['budget'] as num?)?.toDouble() ?? 0;
                final stage = p['stage'] as String? ?? '';
                final color = _stageColors[stage] ?? AppTheme.blue;
                return BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(toY: budget, color: color, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                ]);
              }).toList(),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= projects.length) return const SizedBox.shrink();
                    final name = projects[i]['name'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(name.length > 4 ? '${name.substring(0, 4)}…' : name, style: const TextStyle(fontSize: 10)),
                    );
                  },
                  reservedSize: 24,
                )),
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => Text('\$${value.toInt()}', style: const TextStyle(fontSize: 10)),
                )),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxBudget > 0 ? maxBudget / 4 : 1),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ProjectCalendar extends StatelessWidget {
  final Map<DateTime, List<Map<String, dynamic>>> eventsByDay;
  final List<Map<String, dynamic>> Function(DateTime) eventsForDay;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onPageChanged;
  final bool isDark;

  const _ProjectCalendar({
    required this.eventsByDay,
    required this.eventsForDay,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.isDark,
  });

  Color _eventColor(String? type) {
    switch (type) {
      case 'project_start': return AppTheme.green;
      case 'project_end': return AppTheme.red;
      case 'visit_log': return AppTheme.blue;
      default: return AppTheme.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('项目日历', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TableCalendar(
          firstDay: DateTime(2020),
          lastDay: DateTime(2030),
          focusedDay: focusedDay,
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          onDaySelected: onDaySelected,
          onPageChanged: onPageChanged,
          eventLoader: (day) => eventsForDay(day),
          calendarStyle: CalendarStyle(
            markerDecoration: const BoxDecoration(color: AppTheme.blue, shape: BoxShape.circle),
            todayDecoration: BoxDecoration(color: AppTheme.blue.withAlpha(40), shape: BoxShape.circle),
            selectedDecoration: const BoxDecoration(color: AppTheme.blue, shape: BoxShape.circle),
            outsideDaysVisible: false,
          ),
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return null;
              return Positioned(
                bottom: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: events.take(3).map((e) {
                    final m = e as Map<String, dynamic>;
                    return Container(
                      width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _eventColor(m['type'] as String?)),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
        if (selectedDay != null && eventsForDay(selectedDay!).isNotEmpty) ...[
          const Divider(height: 24),
          ...eventsForDay(selectedDay!).map((e) {
            final title = e['title'] as String? ?? '';
            final type = e['type'] as String? ?? '';
            final color = _eventColor(type);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
              ]),
            );
          }),
        ],
      ]),
    );
  }
}
