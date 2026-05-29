import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/finance_providers.dart';
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
  int _activeView = 0; // 0=dashboard, 1=invoice, 2=budget, 3=expense, 4=voucher

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(financeDashboardProvider.notifier).load());
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
    if (state.data == null) {
      return const Center(child: CircularProgressIndicator());
    }
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
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: double.infinity, child: _KpiCards(data: data, isDark: isDark)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: Padding(padding: const EdgeInsets.only(left: 10), child: _RevenueTrendChart(data: data, isDark: isDark))),
          const SizedBox(height: 20),
          _BudgetUsageSection(data: data, isDark: isDark),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: _QuickActions(onSelect: (i) => setState(() => _activeView = i))),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }
}

// ── KPI Cards ──

class _KpiCards extends StatelessWidget {
  final FinanceDashboardData data;
  final bool isDark;
  const _KpiCards({required this.data, required this.isDark});

  String _fmtAmount(double v) {
    if (v >= 10000) {
      return '¥${(v / 10000).toStringAsFixed(1)}万';
    }
    return '¥${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final pendingTotal = data.pendingInvoices + data.pendingPayments + data.pendingExpenses;

    final cards = [
      (
        '本月收入',
        _fmtAmount(data.monthlyRevenue),
        '月度营收',
        [const Color(0xFF667eea), const Color(0xFF764ba2)],
        [const Color(0xFF667eea).withAlpha(60), const Color(0xFF764ba2).withAlpha(70)],
      ),
      (
        '累计应收',
        _fmtAmount(data.totalReceivable),
        '待回款总额',
        [const Color(0xFFf093fb), const Color(0xFFf5576c)],
        [const Color(0xFFf5576c).withAlpha(60), const Color(0xFFf093fb).withAlpha(50)],
      ),
      (
        '回款率',
        '${(data.collectionRate * 100).toStringAsFixed(1)}%',
        '收款效率',
        [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
        [const Color(0xFF4facfe).withAlpha(60), const Color(0xFF00f2fe).withAlpha(50)],
      ),
      (
        '待处理',
        '$pendingTotal',
        '${data.pendingInvoices} 发票 / ${data.pendingPayments} 付款 / ${data.pendingExpenses} 报销',
        [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
        [const Color(0xFF43e97b).withAlpha(50), const Color(0xFF38f9d7).withAlpha(50)],
      ),
    ];

    final isDesktop = MediaQuery.of(context).size.width >= 768;

    final cardWidgets = cards.map((c) {
      final (label, value, sub, lightGrad, darkGrad) = c;
      final card = Container(
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
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(fontSize: 10, color: Colors.white.withAlpha(170))),
          ],
        ),
      );
      if (isDesktop) {
        return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: card));
      } else {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 32 - 8) / 2,
          child: card,
        );
      }
    }).toList();

    return isDesktop ? Row(children: cardWidgets) : Wrap(spacing: 8, runSpacing: 8, children: cardWidgets);
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
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final trends = data.revenueTrend12m;
    if (trends.isEmpty) return const SizedBox.shrink();

    final spots = trends.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.revenue);
    }).toList();

    final maxRevenue = trends.map((t) => t.revenue).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: isDark ? Border.all(color: AppTheme.darkElevated) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('近12月收入趋势', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        SizedBox(
          height: isDesktop ? 220 : 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxRevenue * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxRevenue > 0 ? maxRevenue / 4 : 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: isDark ? Colors.white12 : Colors.black12,
                    strokeWidth: 1,
                  );
                },
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
                      final label = trends[idx].month.length >= 2
                          ? trends[idx].month.substring(trends[idx].month.length - 2)
                          : trends[idx].month;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(label, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54)),
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
                        child: Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54)),
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
                  color: AppTheme.blue,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 3,
                        color: AppTheme.blue,
                        strokeWidth: 1.5,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppTheme.blue.withAlpha(25),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
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
        borderRadius: BorderRadius.circular(14),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: isDark ? Border.all(color: AppTheme.darkElevated) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('预算使用情况', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        ...budgets.map((b) {
          final pct = b.total > 0 ? (b.used / b.total).clamp(0.0, 1.0) : 0.0;
          final Color barColor;
          if (pct >= 0.9) {
            barColor = AppTheme.red;
          } else if (pct >= 0.7) {
            barColor = AppTheme.orange;
          } else {
            barColor = AppTheme.blue;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(b.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? Colors.white : Colors.black87)),
                ),
                Text(
                  '${b.used.toStringAsFixed(0)} / ${b.total.toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: barColor),
                ),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: isDark ? AppTheme.darkElevated : Colors.grey.shade200,
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
  final void Function(int viewIndex) onSelect;
  const _QuickActions({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final actions = [
      ('发票管理', Icons.receipt_long_rounded, const Color(0xFF667eea)),
      ('预算管理', Icons.account_balance_wallet_rounded, const Color(0xFF4facfe)),
      ('报销管理', Icons.attach_money_rounded, const Color(0xFFf093fb)),
      ('凭证管理', Icons.description_rounded, const Color(0xFFf5576c)),
    ];

    final isDesktop = MediaQuery.of(context).size.width >= 768;

    final actionWidgets = actions.asMap().entries.map((e) {
      final i = e.key;
      final (label, icon, color) = e.value;
      final button = Material(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelect(i + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
            ]),
          ),
        ),
      );
      if (isDesktop) {
        return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: button));
      } else {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 32 - 16) / 3,
          child: button,
        );
      }
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text('快捷操作', style: Theme.of(context).textTheme.titleMedium),
      ),
      isDesktop ? Row(children: actionWidgets) : Wrap(spacing: 8, runSpacing: 8, children: actionWidgets),
    ]);
  }
}
