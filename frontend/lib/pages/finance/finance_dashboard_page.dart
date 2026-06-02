import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/finance_providers.dart';
import '../../services/api_client.dart';
import '../../widgets/watermark.dart';
import '../../models/finance_models.dart';
import 'finance_invoice_page.dart';
import 'finance_budget_page.dart';
import 'finance_expense_page.dart';
import 'finance_voucher_page.dart';

class FinanceDashboardPage extends ConsumerStatefulWidget {
  const FinanceDashboardPage({super.key});
  @override
  ConsumerState<FinanceDashboardPage> createState() => _FinanceDashboardPageState();
}

class _FinanceDashboardPageState extends ConsumerState<FinanceDashboardPage> {
  int _activeView = 0;
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(financeDashboardProvider.notifier).load());
  }

  static const _colorPresets = [
    '#2196F3', '#4CAF50', '#FF9800', '#9C27B0', '#E91E63',
    '#00BCD4', '#FF5722', '#607D8B', '#3F51B5', '#009688',
    '#795548', '#CDDC39',
  ];

  void _showDeptColorDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _api.dio.get('/departments').then((r) => List<Map<String, dynamic>>.from(r.data['items'])),
            builder: (ctx, snap) {
              if (!snap.hasData) return const AlertDialog(title: Text('部门颜色'), content: Center(child: CircularProgressIndicator()));
              final depts = snap.data!;
              return AlertDialog(
                title: const Text('部门颜色'),
                content: SizedBox(
                  width: 340,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: depts.map((d) {
                      final deptId = d['id'] as String;
                      final name = d['name'] as String? ?? '';
                      String colorStr = d['color'] as String? ?? '#2196F3';
                      final curColor = Color(int.parse(colorStr.replaceFirst('#', '0xff')));
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: curColor.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border(left: BorderSide(color: curColor, width: 3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: curColor)),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _colorPresets.map((c) {
                                final sel = colorStr == c;
                                return GestureDetector(
                                  onTap: () {
                                    setDlg(() => colorStr = c);
                                    _api.dio.put('/departments/$deptId', data: {'color': c});
                                  },
                                  child: Container(
                                    width: 32, height: 32, margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: Color(int.parse(c.replaceFirst('#', '0xff'))),
                                      shape: BoxShape.circle,
                                      border: sel ? Border.all(color: Colors.white, width: 3) : null,
                                      boxShadow: sel ? [BoxShadow(color: Color(int.parse(c.replaceFirst('#', '0xff'))).withAlpha(80), blurRadius: 6, spreadRadius: 1)] : null,
                                    ),
                                    child: sel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ]),
                      );
                    }).toList()),
                  ),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final state = ref.watch(financeDashboardProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_activeView == 1) return FinanceInvoicePage(onBack: () => setState(() => _activeView = 0));
    if (_activeView == 2) return FinanceBudgetPage(onBack: () => setState(() => _activeView = 0));
    if (_activeView == 3) return FinanceExpensePage(onBack: () => setState(() => _activeView = 0));
    if (_activeView == 4) return FinanceVoucherPage(onBack: () => setState(() => _activeView = 0));

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('财务')),
        body: _buildBody(state, isDark),
      ),
    );
  }

  Widget _buildBody(FinanceDashboardState state, bool isDark) {
    if (state.data == null) return const Center(child: CircularProgressIndicator());
    if (state.error != null && state.data == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('加载失败', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => ref.read(financeDashboardProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ]),
      );
    }
    final data = state.data!;
    return RefreshIndicator(
      onRefresh: () => ref.read(financeDashboardProvider.notifier).load(),
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        final pad = w >= 800 ? 16.0 : 12.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _KpiCards(data: data, isDark: isDark, width: w),
            const SizedBox(height: 20),
            _RevenueTrendChart(data: data, isDark: isDark),
            const SizedBox(height: 20),
            _BudgetUsageSection(data: data, isDark: isDark),
            const SizedBox(height: 20),
            _QuickActions(onSelect: (i) {
              if (i == 5) { _showDeptColorDialog(); return; }
              setState(() => _activeView = i);
            }, isDark: isDark, width: w),
            const SizedBox(height: 80),
          ]),
        );
      }),
    );
  }
}

// ── KPI Cards ──

class _KpiCards extends StatelessWidget {
  final FinanceDashboardData data;
  final bool isDark;
  final double width;
  const _KpiCards({required this.data, required this.isDark, required this.width});

  String _fmtAmount(double v) {
    if (v >= 10000) return '\u{FFE5}${(v / 10000).toStringAsFixed(1)}万';
    return '\u{FFE5}${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final pendingTotal = data.pendingInvoices + data.pendingPayments + data.pendingExpenses;
    final cards = [
      ('本月收入', _fmtAmount(data.monthlyRevenue), '月度营收', AppTheme.blue),
      ('累计应收', _fmtAmount(data.totalReceivable), '待回款总额', AppTheme.orange),
      ('回款率', '${(data.collectionRate * 100).toStringAsFixed(1)}%', '收款效率', AppTheme.green),
      ('待处理', '$pendingTotal', '${data.pendingInvoices}票据 / ${data.pendingPayments}收款 / ${data.pendingExpenses}审批', AppTheme.pink),
    ];

    if (width >= 800) {
      return Row(children: cards.map((c) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: c == cards.first ? 0 : 6, right: c == cards.last ? 0 : 6),
          child: _kpiCard(c.$1, c.$2, c.$3, c.$4),
        ),
      )).toList());
    }
    final cols = width >= 500 ? 2 : 1;
    final cardW = (width - 12 * (cols + 1)) / cols;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in cards)
        SizedBox(width: cardW, child: _kpiCard(c.$1, c.$2, c.$3, c.$4)),
    ]);
  }

  Widget _kpiCard(String label, String value, String sub, Color accent) {
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
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
      ]),
    );
  }
}

// ── Revenue Trend Chart ──

class _RevenueTrendChart extends StatelessWidget {
  final FinanceDashboardData data;
  final bool isDark;
  const _RevenueTrendChart({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trends = data.revenueTrend12m;
    if (trends.isEmpty) return const SizedBox.shrink();

    final spots = trends.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.revenue)).toList();
    final maxRevenue = trends.map((t) => t.revenue).reduce((a, b) => a > b ? a : b);
    final chartAccent = isDark ? AppTheme.accentLight : AppTheme.accent;

    return LayoutBuilder(builder: (context, constraints) {
      final chartH = constraints.maxWidth >= 900 ? 220.0 : 180.0;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
          border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
          boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('近12月收入趋势', style: theme.textTheme.titleMedium?.copyWith(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
          const SizedBox(height: 16),
          SizedBox(
            height: chartH,
            child: LineChart(LineChartData(
              minY: 0,
              maxY: maxRevenue * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxRevenue > 0 ? maxRevenue / 4 : 1,
                getDrawingHorizontalLine: (value) => FlLine(color: isDark ? Colors.white10 : Colors.black.withAlpha(12), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= trends.length) return const SizedBox.shrink();
                      final label = trends[idx].month.length >= 2 ? trends[idx].month.substring(trends[idx].month.length - 2) : trends[idx].month;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(label, style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    interval: maxRevenue > 0 ? maxRevenue / 4 : 1,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const SizedBox.shrink();
                      final label = value >= 10000 ? '${(value / 10000).toStringAsFixed(0)}万' : '${value.toInt()}';
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(label, style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: chartAccent,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 3, color: chartAccent, strokeWidth: 1.5, strokeColor: isDark ? AppTheme.darkSurface : Colors.white),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: isDark ? AppTheme.accentLight.withAlpha(15) : AppTheme.accent.withAlpha(20),
                  ),
                ),
              ],
            )),
          ),
        ]),
      );
    });
  }
}

// ── Budget Usage Section ──

class _BudgetUsageSection extends StatelessWidget {
  final FinanceDashboardData data;
  final bool isDark;
  const _BudgetUsageSection({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budgets = data.budgetUsage;
    if (budgets.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('预算使用情况', style: theme.textTheme.titleMedium?.copyWith(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
        const SizedBox(height: 14),
        ...budgets.map((b) {
          final pct = b.total > 0 ? (b.used / b.total).clamp(0.0, 1.0) : 0.0;
          final barColor = pct >= 0.9 ? AppTheme.red : pct >= 0.7 ? AppTheme.orange : AppTheme.accent;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(b.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
                Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: barColor)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: barColor.withAlpha(isDark ? 20 : 15),
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── Quick Actions ──

class _QuickActions extends StatelessWidget {
  final void Function(int) onSelect;
  final bool isDark;
  final double width;
  const _QuickActions({required this.onSelect, required this.isDark, required this.width});

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('发票管理', Icons.receipt_long_rounded, AppTheme.blue),
      ('预算管理', Icons.account_balance_wallet_rounded, AppTheme.green),
      ('支出管理', Icons.attach_money_rounded, AppTheme.orange),
      ('凭证管理', Icons.description_rounded, AppTheme.purple),
      ('部门颜色', Icons.palette_rounded, AppTheme.teal),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text('快捷操作', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: isDark ? AppTheme.darkText : AppTheme.lightText)),
      ),
      if (width >= 600)
        Row(children: actions.asMap().entries.map((e) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: e.key == 0 ? 0 : 4, right: e.key == actions.length - 1 ? 0 : 4),
            child: _actionCard(e.value.$1, e.value.$2, e.value.$3, () => onSelect(e.key + 1)),
          ),
        )).toList())
      else
        _wrapActions(actions),
    ]);
  }

  Widget _wrapActions(List<(String, IconData, Color)> actions) {
    final cols = width >= 360 ? 3 : 2;
    final cardW = (width - 12 * (cols + 1)) / cols;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < actions.length; i++)
        SizedBox(width: cardW, child: _actionCard(actions[i].$1, actions[i].$2, actions[i].$3, () => onSelect(i + 1))),
    ]);
  }

  Widget _actionCard(String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withAlpha(isDark ? 20 : 15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withAlpha(30)),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }
}
