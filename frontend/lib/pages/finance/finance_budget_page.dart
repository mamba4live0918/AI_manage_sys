import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/finance_providers.dart';
import '../../models/finance_models.dart';
import '../../services/api_client.dart';

class FinanceBudgetPage extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const FinanceBudgetPage({super.key, this.onBack});

  @override
  ConsumerState<FinanceBudgetPage> createState() => _FinanceBudgetPageState();
}

class _FinanceBudgetPageState extends ConsumerState<FinanceBudgetPage> {
  final ApiClient _api = ApiClient();
  final Map<String, Map<String, dynamic>> _consumptionCache = {};
  final Map<String, List<Map<String, dynamic>>> _projectListCache = {};
  bool _loadingProjects = false;
  Map<String, dynamic>? _summary;
  bool _summaryExpanded = false;
  final Set<String> _expandedNodes = {};

  static const _statusLabels = {
    'active': '进行中',
    'closed': '已关闭',
    'frozen': '已冻结',
  };
  static const _statusColors = {
    'active': Colors.green,
    'closed': Colors.grey,
    'frozen': Colors.orange,
  };
  static const _categoryLabels = {
    'travel': '差旅',
    'office': '办公',
    'entertainment': '招待',
    'equipment': '设备',
    'salary': '工资',
    'training': '培训',
    'marketing': '市场',
    'other': '其他',
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(financeBudgetProvider.notifier).load();
      _loadSummary();
    });
  }

  Future<List<Map<String, dynamic>>> _loadProjects() async {
    if (_projectListCache.containsKey('all')) return _projectListCache['all']!;
    if (_loadingProjects) return [];
    _loadingProjects = true;
    try {
      final resp = await _api.dio.get('/pm/projects', queryParameters: {'limit': '200'});
      final items = List<Map<String, dynamic>>.from(resp.data['items'] ?? []);
      _projectListCache['all'] = items;
      return items;
    } catch (_) {
      return [];
    } finally {
      _loadingProjects = false;
    }
  }

  Future<Map<String, dynamic>> _loadConsumption(String budgetId) async {
    if (_consumptionCache.containsKey(budgetId)) return _consumptionCache[budgetId]!;
    try {
      final resp = await _api.dio.get('/finance/budgets/$budgetId/consumption');
      _consumptionCache[budgetId] = resp.data;
      return resp.data;
    } catch (_) {
      return {};
    }
  }

  Future<void> _loadSummary() async {
    try {
      final resp = await _api.dio.get('/finance/budgets/summary');
      if (mounted) setState(() => _summary = resp.data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeBudgetProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('预算管理'),
        leading: widget.onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('暂无预算', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    ref.read(financeBudgetProvider.notifier).load();
                    _loadSummary();
                  },
                  child: _buildBudgetTree(context, state.items),
                ),
    );
  }

  Widget _buildBudgetTree(BuildContext context, List<BudgetData> items) {
    final roots = items.where((b) => b.parentId == null).toList();

    if (roots.isEmpty && items.isNotEmpty) {
      // All budgets have parents but no roots found — show flat list
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: items.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return _buildSummaryCard(context);
          return _buildBudgetCard(context, items[i - 1]);
        },
      );
    }

    // Build flat list from tree
    final flatList = <Widget>[];
    flatList.add(_buildSummaryCard(context));
    for (final root in roots) {
      flatList.add(_buildBudgetCard(context, root));
      if (_expandedNodes.contains(root.id)) {
        final children = items.where((b) => b.parentId == root.id).toList();
        for (final child in children) {
          flatList.add(
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _buildBudgetCard(context, child, isChild: true),
            ),
          );
          if (_expandedNodes.contains(child.id)) {
            final grandchildren = items.where((b) => b.parentId == child.id).toList();
            for (final gc in grandchildren) {
              flatList.add(
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: _buildBudgetCard(context, gc, isChild: true),
                ),
              );
            }
          }
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: flatList,
    );
  }

  Widget _buildBudgetCard(BuildContext context, BudgetData b, {bool isChild = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pct = b.totalAmount > 0 ? (b.usedAmount / b.totalAmount).clamp(0.0, 1.0) : 0.0;
    final statusLabel = _statusLabels[b.status] ?? b.status;
    final statusColor = _statusColors[b.status] ?? Colors.grey;
    final warnColor = pct > 0.9 ? AppTheme.green : pct > 0.7 ? Colors.orange : Colors.green;
    final hasChildren = ref.watch(financeBudgetProvider).items.any((i) => i.parentId == b.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            if (_expandedNodes.contains(b.id)) {
              _expandedNodes.remove(b.id);
            } else {
              _expandedNodes.add(b.id);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: name + status + menu
              Row(children: [
                Expanded(
                  child: Row(children: [
                    if (isChild) ...[
                      if (b.quarter != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('季', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blue)),
                        ),
                      if (b.departmentId != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('部', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.teal)),
                        ),
                    ],
                    Flexible(
                      child: Text(b.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _yearQuarterBgColor(b, isDark),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _yearQuarterLabel(b),
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  ]),
                ),
                if (hasChildren)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      _expandedNodes.contains(b.id) ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      size: 18,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: statusColor)),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: isDark ? Colors.white70 : Colors.black54),
                  onSelected: (v) {
                    if (v == 'edit') _showEditDialog(context, b);
                    if (v == 'delete') _confirmDelete(context, b.id, b.name);
                    if (v == 'adjust') _showAdjustDialog(context, b);
                    if (v == 'add_child') _showCreateDialog(context, parent: b);
                    if (v == 'add_category') _showAddCategoryItemDialog(context, b);
                  },
                  itemBuilder: (_) {
                    final isLeaf = b.quarter != null && b.departmentId != null;
                    final isQuarter = b.quarter != null && b.departmentId == null;
                    final childLabel = isLeaf
                        ? '添加分类预算'
                        : isQuarter
                            ? '添加Q${b.quarter}部门预算'
                            : '添加季度预算';
                    return [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 20), SizedBox(width: 8), Text('编辑')])),
                      PopupMenuItem(value: isLeaf ? 'add_category' : 'add_child', child: Row(children: [Icon(Icons.subdirectory_arrow_right, size: 20, color: AppTheme.accent), SizedBox(width: 8), Text(childLabel, style: const TextStyle(color: AppTheme.accent))])),
                      const PopupMenuItem(value: 'adjust', child: Row(children: [Icon(Icons.tune, size: 20), SizedBox(width: 8), Text('调整')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 20), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                    ];
                  },
                ),
              ]),
              const SizedBox(height: 12),
              // Row 2: stacked progress bar
              _buildStackedProgressBar(b, isDark),
              const SizedBox(height: 8),
              // Row 3: amounts
              Row(children: [
                Text('已用: ${_fmt(b.usedAmount)}',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                const Spacer(),
                Text('总额: ${_fmt(b.totalAmount)}',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                const Spacer(),
                Text('${(pct * 100).toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: warnColor)),
              ]),
              const SizedBox(height: 8),
              // Row 4: mini breakdown — fee vs settlement
              Row(children: [
                _miniChip('费用', b.usedAmount, warnColor, isDark),
                const SizedBox(width: 12),
                _miniChip('结算', 0, Colors.blue, isDark),
                const Spacer(),
                Text('剩余: ${_fmt(b.totalAmount - b.usedAmount)}',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String label, double amount, Color color, bool isDark) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label ${_fmt(amount)}',
          style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black45)),
    ]);
  }

  Widget _buildStackedProgressBar(BudgetData b, bool isDark) {
    final items = b.items.where((i) => i.amount > 0).toList();
    final pct = b.totalAmount > 0 ? (b.usedAmount / b.totalAmount).clamp(0.0, 1.0) : 0.0;

    if (items.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 10,
          child: Stack(children: [
            Container(color: isDark ? Colors.white12 : Colors.grey.shade200),
            if (pct > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct,
                  child: CustomPaint(
                    painter: _CheckerboardPainter(isDark: isDark),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ]),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            final totalW = constraints.maxWidth;
            final itemSum = items.fold<double>(0, (s, i) => s + i.amount);
            final displayTotal = itemSum > 0 ? (itemSum < b.totalAmount ? b.totalAmount : itemSum) : (b.totalAmount > 0 ? b.totalAmount : 1);
            final sorted = List<BudgetItemData>.from(items)
              ..sort((a, b) => b.amount.compareTo(a.amount));
            final segments = <Widget>[];
            double usedW = 0;
            for (final item in sorted) {
              final segW = (item.amount / displayTotal) * totalW;
              if (segW >= 2) {
                usedW += segW;
                final spentPct = item.amount > 0 ? (item.usedAmount / item.amount).clamp(0.0, 1.0) : 0.0;
                segments.add(SizedBox(
                  width: segW,
                  child: Stack(children: [
                    Container(color: _itemColor(item)),
                    if (spentPct > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: spentPct,
                          child: CustomPaint(
                            painter: _CheckerboardPainter(isDark: isDark),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                  ]),
                ));
              }
            }
            final unallocated = b.totalAmount - itemSum;
            if (unallocated > 0 && totalW - usedW >= 2) {
              segments.add(SizedBox(width: totalW - usedW, child: Container(color: Colors.grey.shade400)));
            }
            if (segments.isEmpty) return Container(color: isDark ? Colors.white12 : Colors.grey.shade200);
            return Row(children: segments);
          },
        ),
      ),
    );
  }

  Color _yearQuarterBgColor(BudgetData b, bool isDark) {
    if (b.quarter != null) return Colors.blue.withValues(alpha: 0.1);
    return isDark ? Colors.white12 : Colors.grey.shade100;
  }

  String _yearQuarterLabel(BudgetData b) {
    if (b.quarter != null) return '${b.year}年 Q${b.quarter}';
    return '${b.year}年';
  }

  String _fmt(double val) {
    if (val.abs() >= 10000) return '\u{FFE5}${(val / 10000).toStringAsFixed(1)}万';
    return '\u{FFE5}${val.toStringAsFixed(0)}';
  }

  String _categoryLabel(String cat) {
    return _categoryLabels[cat] ?? cat;
  }

  // ── Budget Detail Bottom Sheet ──

  void _showBudgetDetail(BuildContext context, BudgetData b) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            return FutureBuilder<Map<String, dynamic>>(
              future: _loadConsumption(b.id),
              builder: (ctx, snapshot) {
                final consumption = snapshot.data ?? {};
                final expenseBreakdown = (consumption['expense_breakdown'] as List?) ?? [];
                final settlementTotal = (consumption['settlement_total'] as num?)?.toDouble() ?? 0;
                final recentExpenses = (consumption['recent_expenses'] as List?) ?? [];

                final expenseTotal = expenseBreakdown.fold<double>(0, (s, e) => s + ((e['total'] as num?)?.toDouble() ?? 0));
                final statusLabel = _statusLabels[b.status] ?? b.status;
                final statusColor = _statusColors[b.status] ?? Colors.grey;
                final pct = b.totalAmount > 0 ? (b.usedAmount / b.totalAmount).clamp(0.0, 1.0) : 0.0;
                final warnColor = pct > 0.9 ? AppTheme.green : pct > 0.7 ? Colors.orange : Colors.green;
                final remaining = b.totalAmount - b.usedAmount;

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  children: [
                    // Handle
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    // Header
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(b.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                          const SizedBox(height: 4),
                          Text(_yearQuarterLabel(b), style: TextStyle(fontSize: 13, color: labelColor)),
                        ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(statusLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEditDialog(context, b);
                        },
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // Overview card
                    _sectionTitle('概览', textColor),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(isDark),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Progress bar: chessboard used + colored remaining
                        Container(
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: (pct >= 0.9 ? AppTheme.red : pct >= 0.7 ? AppTheme.orange : AppTheme.accent).withAlpha(isDark ? 18 : 10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: LayoutBuilder(builder: (_, c) => Stack(children: [
                            if (pct > 0)
                              Positioned(
                                left: 0, top: 0, bottom: 0,
                                width: c.maxWidth * pct,
                                child: CustomPaint(
                                  painter: _BarCheckerPainter(baseColor: const Color(0xFFD4D4DC)),
                                ),
                              ),
                            Positioned(
                              left: c.maxWidth * pct, top: 0, bottom: 0, right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6)),
                                  gradient: LinearGradient(colors: [
                                    pct >= 0.9 ? AppTheme.red : pct >= 0.7 ? AppTheme.orange : AppTheme.accent,
                                    (pct >= 0.9 ? AppTheme.red : pct >= 0.7 ? AppTheme.orange : AppTheme.accent).withAlpha(180),
                                  ]),
                                ),
                              ),
                            ),
                            if (pct > 0.12)
                              Positioned(left: 10, top: 0, bottom: 0, child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('已用 \u{FFE5}${_fmt(b.usedAmount)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6B6B8A))),
                              )),
                            Positioned(right: 10, top: 0, bottom: 0, child: Align(
                              alignment: Alignment.centerRight,
                              child: Text('剩余 \u{FFE5}${_fmt(remaining)}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: pct > 0.6 ? Colors.white : (isDark ? AppTheme.darkText : AppTheme.lightText))),
                            )),
                          ])),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          _amountColumn('预算总额', b.totalAmount, textColor, labelColor),
                          _amountColumn('已使用', b.usedAmount, warnColor, labelColor),
                          _amountColumn('剩余', remaining > 0 ? remaining : 0, remaining >= 0 ? Colors.green : Colors.red, labelColor),
                        ]),
                        const SizedBox(height: 8),
                        Text('使用率 ${(pct * 100).toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: warnColor)),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Budget items breakdown
                    Row(children: [
                      _sectionTitle('预算项目详情', textColor),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加分类'),
                        onPressed: () => _showAddCategoryItemDialog(ctx, b),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    else ...[
                      if (b.items.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: _cardDecoration(isDark),
                          child: Column(children: [
                            ...b.items.map((item) {
                              final itemPct = b.totalAmount > 0 ? (item.amount / b.totalAmount * 100).clamp(0.0, 100.0) : 0.0;
                              final usedPct = item.amount > 0 ? (item.usedAmount / item.amount * 100).clamp(0.0, 100.0) : 0.0;
                              final catColor = _itemColor(item);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(_iconFromName(item.icon), size: 16, color: catColor),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(item.name.isNotEmpty ? '${_categoryLabel(item.category)} - ${item.name}' : _categoryLabel(item.category),
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
                                    ),
                                    Text(_fmt(item.amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                                  ]),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: SizedBox(
                                      height: 6,
                                      child: Stack(children: [
                                        Container(color: catColor.withValues(alpha: 0.12)),
                                        if (usedPct > 0)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: FractionallySizedBox(
                                              widthFactor: usedPct / 100,
                                              child: CustomPaint(
                                                painter: _CheckerboardPainter(isDark: isDark),
                                                child: const SizedBox.expand(),
                                              ),
                                            ),
                                          ),
                                      ]),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Text('已用 ${_fmt(item.usedAmount)}', style: TextStyle(fontSize: 11, color: labelColor)),
                                    const Spacer(),
                                    Text('${itemPct.toStringAsFixed(0)}% / ${usedPct.toStringAsFixed(0)}%',
                                        style: TextStyle(fontSize: 11, color: usedPct > 90 ? Colors.red : labelColor)),
                                  ]),
                                ]),
                              );
                            }),
                            const Divider(height: 16),
                          ]),
                        ),
                      // Unallocated amount
                      Builder(builder: (_) {
                        final itemTotal = b.items.fold(0.0, (s, i) => s + i.amount);
                        final unallocated = b.totalAmount - itemTotal;
                        if (unallocated > 0) {
                          return Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
                            ),
                            child: Row(children: [
                              Container(
                                width: 16, height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade400,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.remove, size: 10, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              Text('未分配', style: TextStyle(fontSize: 13, color: labelColor)),
                              const Spacer(),
                              Text(_fmt(unallocated), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                            ]),
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                      // Total
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: _cardDecoration(isDark),
                        child: Row(children: [
                          Text('预算总额', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                          const Spacer(),
                          Text(_fmt(b.totalAmount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Expense breakdown
                    _sectionTitle('费用明细', textColor),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    else if (expenseBreakdown.isEmpty)
                      _emptyHint('暂无费用记录', isDark)
                    else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: _cardDecoration(isDark),
                        child: Column(children: [
                          ...expenseBreakdown.map((e) {
                            final cat = e['category'] as String? ?? 'other';
                            final total = (e['total'] as num?)?.toDouble() ?? 0;
                            final count = e['count'] as int? ?? 0;
                            final catPct = expenseTotal > 0 ? total / expenseTotal : 0.0;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColor(cat), shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_categoryLabel(cat), style: TextStyle(fontSize: 13, color: textColor))),
                                Text('$count 笔', style: TextStyle(fontSize: 11, color: labelColor)),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 80,
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                    Text(_fmt(total), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
                                    Text('${(catPct * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, color: labelColor)),
                                  ]),
                                ),
                              ]),
                            );
                          }),
                          const Divider(height: 20),
                          Row(children: [
                            Text('费用合计', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                            const Spacer(),
                            Text(_fmt(expenseTotal), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: warnColor)),
                          ]),
                          if (settlementTotal > 0) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Text('结算合计', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                              const Spacer(),
                              Text(_fmt(settlementTotal), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue)),
                            ]),
                          ],
                        ]),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Recent expense items
                    _sectionTitle('最近费用记录', textColor),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    else if (recentExpenses.isEmpty)
                      _emptyHint('暂无费用记录', isDark)
                    else
                      Container(
                        decoration: _cardDecoration(isDark),
                        child: Column(
                          children: recentExpenses.map<Widget>((e) {
                            final cat = e['category'] as String? ?? 'other';
                            final amount = (e['amount'] as num?)?.toDouble() ?? 0;
                            final desc = e['description'] as String? ?? '';
                            final date = e['date'] as String? ?? '';
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: _catColor(cat).withValues(alpha: 0.12),
                                child: Icon(_catIcon(cat), size: 16, color: _catColor(cat)),
                              ),
                              title: Text(_categoryLabel(cat), style: TextStyle(fontSize: 13, color: textColor)),
                              subtitle: Text(desc.isNotEmpty ? desc : date, style: TextStyle(fontSize: 11, color: labelColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text(_fmt(amount), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor)),
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Quick actions
                    _sectionTitle('快捷操作', textColor),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('调整预算'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showAdjustDialog(context, b);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑预算'),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showEditDialog(context, b);
                          },
                        ),
                      ),
                    ]),
                    SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _sectionTitle(String title, Color color) {
    return Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color));
  }

  Widget _amountColumn(String label, double value, Color valueColor, Color labelColor) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(_fmt(value), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: labelColor)),
      ]),
    );
  }

  Widget _emptyHint(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(isDark),
      child: Center(child: Text(text, style: TextStyle(color: Colors.grey.shade500, fontSize: 13))),
    );
  }

  BoxDecoration _cardDecoration(bool isDark) {
    return BoxDecoration(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
    );
  }

  Color _catColor(String cat) {
    switch (cat) {
      case 'travel': return Colors.orange;
      case 'office': return Colors.blue;
      case 'entertainment': return Colors.purple;
      case 'equipment': return Colors.teal;
      case 'salary': return Colors.green;
      case 'training': return Colors.indigo;
      case 'marketing': return Colors.pink;
      case 'other': return Colors.grey;
      default: return Colors.grey;
    }
  }

  Color _itemColor(BudgetItemData item) {
    try {
      final c = item.color;
      if (c.isEmpty || c == '#FF0000') return _catColor(item.category);
      return Color(int.parse(c.replaceFirst('#', '0xff')));
    } catch (_) {
      return _catColor(item.category);
    }
  }

  IconData _catIcon(String cat) {
    switch (cat) {
      case 'travel': return Icons.flight;
      case 'office': return Icons.description;
      case 'entertainment': return Icons.celebration;
      case 'equipment': return Icons.devices;
      case 'salary': return Icons.monetization_on;
      case 'training': return Icons.school;
      case 'marketing': return Icons.campaign;
      default: return Icons.receipt_long;
    }
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'receipt': return Icons.receipt;
      case 'flight': return Icons.flight;
      case 'directions_car': return Icons.directions_car;
      case 'restaurant': return Icons.restaurant;
      case 'devices': return Icons.devices;
      case 'monetization_on': return Icons.monetization_on;
      case 'school': return Icons.school;
      case 'campaign': return Icons.campaign;
      case 'card_giftcard': return Icons.card_giftcard;
      case 'local_shipping': return Icons.local_shipping;
      case 'medical_services': return Icons.medical_services;
      case 'build': return Icons.build;
      case 'security': return Icons.security;
      case 'pets': return Icons.pets;
      case 'emoji_events': return Icons.emoji_events;
      case 'construction': return Icons.construction;
      case 'brush': return Icons.brush;
      case 'cloud': return Icons.cloud;
      case 'more_horiz': return Icons.more_horiz;
      default: return Icons.description;
    }
  }

  Widget _iconPickerRow(String currentIcon, ValueChanged<String> onChanged) {
    final icons = ['description', 'receipt', 'flight', 'directions_car', 'restaurant', 'devices', 'monetization_on', 'school', 'campaign', 'card_giftcard', 'local_shipping', 'medical_services', 'build', 'security', 'pets', 'emoji_events', 'construction', 'brush', 'cloud', 'more_horiz'];
    return SizedBox(height: 44, child: ListView(
      scrollDirection: Axis.horizontal,
      children: icons.map((name) {
          final iconData = _iconFromName(name);
          final selected = currentIcon == name;
          return GestureDetector(
            onTap: () => onChanged(name),
            child: Container(
              width: 40, height: 40,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: selected ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: selected ? Border.all(color: Colors.blue, width: 2) : null,
              ),
              child: Icon(iconData, size: 20, color: selected ? Colors.blue : Colors.grey),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Edit Dialog ──

  void _showEditDialog(BuildContext context, BudgetData budget) {
    final nameCtrl = TextEditingController(text: budget.name);
    final yearCtrl = TextEditingController(text: budget.year.toString());
    final quarterCtrl = TextEditingController(text: budget.quarter?.toString() ?? '');
    final notesCtrl = TextEditingController(text: budget.notes);
    String budgetStatus = budget.status;

    // Pre-fill existing items
    final List<Map<String, dynamic>> items = budget.items.isNotEmpty
        ? budget.items.map((item) => _newItemEntry(item.category, item.name, item.amount.toStringAsFixed(0), color: item.color, icon: item.icon)).toList()
        : [_newItemEntry('other', '', '0')];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final itemTotal = items.fold<double>(0, (s, item) {
            final amt = double.tryParse((item['amountCtrl'] as TextEditingController).text) ?? 0;
            return s + amt;
          });

          return AlertDialog(
            title: const Text('编辑预算'),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '预算名称')),
                  TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: '年度'), keyboardType: TextInputType.number),
                  TextField(controller: quarterCtrl, decoration: const InputDecoration(labelText: '季度 (1-4, 留空=全年)'), keyboardType: TextInputType.number),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: '备注说明'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: budgetStatus,
                    decoration: const InputDecoration(labelText: '状态'),
                    items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDialogState(() => budgetStatus = v ?? budget.status),
                  ),
                  const SizedBox(height: 16),
                  // ── Line Items Section ──
                  Row(children: [
                    const Text('预算项目', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加'),
                      onPressed: () {
                        setDialogState(() {
                          items.add(_newItemEntry('other', '', '0'));
                        });
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  ...List.generate(items.length, (i) {
                    final item = items[i];
                    final catCtrl = item['cat'] as String;
                    final nameCtrl = item['nameCtrl'] as TextEditingController;
                    final amountCtrl = item['amountCtrl'] as TextEditingController;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: catCtrl,
                                isDense: true,
                                decoration: const InputDecoration(labelText: '类别', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                items: _categoryLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                                onChanged: (v) => setDialogState(() => items[i]['cat'] = v ?? 'other'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: nameCtrl,
                                decoration: const InputDecoration(labelText: '名称', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            Expanded(
                              child: TextField(
                                controller: amountCtrl,
                                decoration: const InputDecoration(labelText: '金额', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                            if (items.length > 1)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                onPressed: () => setDialogState(() => items.removeAt(i)),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          _colorPickerRow(item['color'] as String, (c) => setDialogState(() => items[i]['color'] = c)),
                          const SizedBox(height: 4),
                          _iconPickerRow(item['icon'] as String, (ic) => setDialogState(() => items[i]['icon'] = ic)),
                        ]),
                      ),
                    );
                  }),
                  // Total
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '合计: ${_fmt(itemTotal)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]),
              ),
            ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(onPressed: () async {
                try {
                  int? quarter;
                  if (quarterCtrl.text.isNotEmpty) {
                    quarter = int.tryParse(quarterCtrl.text);
                  }
                  final itemsList = items.map((item) => {
                    'category': item['cat'] as String,
                    'name': (item['nameCtrl'] as TextEditingController).text,
                    'amount': double.tryParse((item['amountCtrl'] as TextEditingController).text) ?? 0,
                    'color': item['color'] as String,
                    'icon': item['icon'] as String,
                  }).toList();
                  await _api.dio.put('/finance/budgets/${budget.id}', data: {
                    'name': nameCtrl.text,
                    'year': int.tryParse(yearCtrl.text) ?? budget.year,
                    'quarter': quarter,
                    'status': budgetStatus,
                    'notes': notesCtrl.text,
                    'items': itemsList,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _consumptionCache.remove(budget.id);
                  ref.read(financeBudgetProvider.notifier).load();
                  _loadSummary();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('更新成功')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
                  }
                }
              }, child: const Text('保存')),
            ],
          );
        },
      ),
    );
  }

  // ── Adjust Dialog ──

  void _showAdjustDialog(BuildContext context, BudgetData budget) {
    final adjustCtrl = TextEditingController();
    bool isAdd = true;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('调整预算'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('当前总额: ${_fmt(budget.totalAmount)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                Text('已使用: ${_fmt(budget.usedAmount)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('追加', style: TextStyle(fontSize: 13))),
                        ButtonSegment(value: false, label: Text('调减', style: TextStyle(fontSize: 13))),
                      ],
                      selected: {isAdd},
                      onSelectionChanged: (v) => setDialogState(() => isAdd = v.first),
                    ),
                  ),
                ]),
                TextField(
                  controller: adjustCtrl,
                  decoration: InputDecoration(
                    labelText: isAdd ? '追加金额' : '调减金额',
                    errorText: errorMsg,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () async {
              final adjustAmount = double.tryParse(adjustCtrl.text);
              if (adjustAmount == null || adjustAmount <= 0) {
                setDialogState(() => errorMsg = '请输入有效金额');
                return;
              }
              final newTotal = isAdd ? budget.totalAmount + adjustAmount : budget.totalAmount - adjustAmount;
              if (newTotal < budget.usedAmount) {
                setDialogState(() => errorMsg = '调整后总额不能低于已使用金额');
                return;
              }
              try {
                await _api.dio.put('/finance/budgets/${budget.id}', data: {
                  'total_amount': newTotal,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _consumptionCache.remove(budget.id);
                ref.read(financeBudgetProvider.notifier).load();
                _loadSummary();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('预算调整成功')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('调整失败: $e')));
                }
              }
            }, child: const Text('确认调整')),
          ],
        ),
      ),
    );
  }

  // ── Add Category Item Dialog ──

  void _showAddCategoryItemDialog(BuildContext parentContext, BudgetData budget) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String selectedCategory = 'other';
    String selectedColor = '#4CAF50';
    String selectedIcon = 'description';
    String? amountError;

    final itemTotal = budget.items.fold(0.0, (s, i) => s + i.amount);
    final remaining = budget.totalAmount - itemTotal;

    showDialog(
      context: parentContext,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加分类项目'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(parentContext).size.height * 0.55),
            child: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('剩余可分配: ${_fmt(remaining)}', style: TextStyle(fontSize: 13, color: Colors.blue.shade600, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: '类别'),
                    items: _categoryLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDialogState(() => selectedCategory = v ?? 'other'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '项目名称', hintText: '例如：Google Ads投放'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                      labelText: '金额',
                      errorText: amountError,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  Text('颜色', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  _colorPickerRow(selectedColor, (c) => setDialogState(() => selectedColor = c)),
                  const SizedBox(height: 8),
                  Text('图标', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  _iconPickerRow(selectedIcon, (ic) => setDialogState(() => selectedIcon = ic)),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () async {
              final amount = double.tryParse(amountCtrl.text);
              if (amount == null || amount <= 0) {
                setDialogState(() => amountError = '请输入有效金额');
                return;
              }
              if (amount > remaining) {
                setDialogState(() => amountError = '不能超过剩余可分配金额 (${_fmt(remaining)})');
                return;
              }
              try {
                final newItems = <Map<String, dynamic>>[];
                for (final item in budget.items) {
                  newItems.add({
                    'category': item.category,
                    'name': item.name,
                    'amount': item.amount,
                    'color': item.color,
                    'icon': item.icon,
                  });
                }
                newItems.add({
                  'category': selectedCategory,
                  'name': nameCtrl.text,
                  'amount': amount,
                  'color': selectedColor,
                  'icon': selectedIcon,
                });
                await _api.dio.put('/finance/budgets/${budget.id}', data: {
                  'items': newItems,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _consumptionCache.remove(budget.id);
                ref.read(financeBudgetProvider.notifier).load();
                _loadSummary();
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext).showSnackBar(const SnackBar(content: Text('分类项目添加成功')));
                }
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext).showSnackBar(SnackBar(content: Text('添加失败: $e')));
                }
              }
            }, child: const Text('保存')),
          ],
        ),
      ),
    );
  }

  // ── Create Dialog ──

  void _showCreateDialog(BuildContext context, {BudgetData? parent}) {
    final authState = ref.read(authProvider);
    final currentUser = authState.user;
    final dialogTitle = _childBudgetTitle(parent);
    final defaultName = parent != null
        ? (parent.quarter == null
            ? 'Q'
            : '${parent.name} Q${parent.quarter} - ')
        : '';
    final nameCtrl = TextEditingController(text: defaultName);
    final yearCtrl = TextEditingController(text: parent?.year.toString() ?? '2026');
    final quarterCtrl = TextEditingController(
      text: parent?.quarter?.toString() ?? '',
    );
    final totalAmountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? selectedProjectId;
    String? selectedDeptId;
    List<Map<String, dynamic>>? deptList;
    bool deptListLoading = false;
    String selectedStatus = 'active';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(dialogTitle),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '预算名称', hintText: '例如：2026年Q1市场部预算')),
                  TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: '年度'), keyboardType: TextInputType.number),
                  TextField(controller: quarterCtrl, decoration: const InputDecoration(labelText: '季度 (1-4, 留空=全年)'), keyboardType: TextInputType.number),
                  TextField(controller: totalAmountCtrl, decoration: const InputDecoration(labelText: '预算总额'), keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  // ── Department section ──
                  currentUser != null && currentUser.departmentId != null
                      ? Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.business, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text('所属部门: ${currentUser.department}',
                                style: const TextStyle(fontSize: 13, color: Colors.blue)),
                          ]),
                        )
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text('请先选择部门', style: TextStyle(fontSize: 13, color: Colors.orange)),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 8),
                          deptList == null && !deptListLoading
                              ? TextButton.icon(
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('加载部门列表'),
                                  onPressed: () async {
                                    setDialogState(() => deptListLoading = true);
                                    try {
                                      final resp = await _api.dio.get('/departments');
                                      setDialogState(() {
                                        deptList = List<Map<String, dynamic>>.from(resp.data['items']);
                                        deptListLoading = false;
                                      });
                                    } catch (_) {
                                      setDialogState(() => deptListLoading = false);
                                    }
                                  },
                                )
                              : deptListLoading
                                  ? const SizedBox(height: 24, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
                                  : DropdownButtonFormField<String>(
                                      value: selectedDeptId,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: '选择部门',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      ),
                                      items: (deptList ?? []).map((d) => DropdownMenuItem(
                                        value: d['id'] as String?,
                                        child: Text(d['name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                                      )).toList(),
                                      onChanged: (v) => setDialogState(() => selectedDeptId = v),
                                    ),
                        ]),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _loadProjects(),
                    builder: (ctx, snap) {
                      final projects = snap.data ?? [];
                      return DropdownButtonFormField<String>(
                        initialValue: selectedProjectId,
                        decoration: const InputDecoration(labelText: '关联项目 (可选)'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('无')),
                          ...projects.map((p) => DropdownMenuItem(
                            value: p['id'] as String?,
                            child: Text(p['name'] ?? '', overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (v) => setDialogState(() => selectedProjectId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(labelText: '状态'),
                    items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDialogState(() => selectedStatus = v ?? 'active'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: '备注说明'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Text('创建后可添加分类项目', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ]),
              ),
            ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(onPressed: () async {
                final totalAmount = double.tryParse(totalAmountCtrl.text);
                if (totalAmount == null || totalAmount <= 0) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效的预算总额')));
                  }
                  return;
                }
                try {
                  int? quarter;
                  if (quarterCtrl.text.isNotEmpty) {
                    quarter = int.tryParse(quarterCtrl.text);
                  }
                  final data = <String, dynamic>{
                    'name': nameCtrl.text,
                    'year': int.tryParse(yearCtrl.text) ?? 2026,
                    'quarter': quarter,
                    'total_amount': totalAmount,
                    'status': selectedStatus,
                  };
                  if (selectedDeptId != null) data['department_id'] = selectedDeptId;
                  if (selectedProjectId != null) data['project_id'] = selectedProjectId;
                  if (parent != null) data['parent_id'] = parent.id;
                  if (notesCtrl.text.isNotEmpty) data['notes'] = notesCtrl.text;
                  await _api.dio.post('/finance/budgets', data: data);
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.read(financeBudgetProvider.notifier).load();
                  _loadSummary();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('预算创建成功')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
                  }
                }
              }, child: const Text('创建')),
            ],
          );
        },
      ),
    );
  }

  String _childBudgetTitle(BudgetData? parent) {
    if (parent == null) return '创建预算（资金池）';
    if (parent.quarter == null) return '添加季度预算';
    if (parent.departmentId == null) return '添加Q${parent.quarter}部门预算';
    return '添加分类预算';
  }

  Map<String, dynamic> _newItemEntry(String cat, String name, String amount, {String color = '#FF0000', String icon = 'description'}) {
    return {
      'cat': cat,
      'nameCtrl': TextEditingController(text: name),
      'amountCtrl': TextEditingController(text: amount),
      'color': color,
      'icon': icon,
    };
  }

  Widget _colorPickerRow(String currentColor, ValueChanged<String> onChanged) {
    final presets = ['#FF0000', '#FF5722', '#FF9800', '#FFEB3B', '#4CAF50', '#2196F3', '#3F51B5', '#9C27B0', '#E91E63', '#009688', '#607D8B'];
    return SizedBox(height: 32, child: ListView(scrollDirection: Axis.horizontal, children: [
      ...presets.map((c) => GestureDetector(
        onTap: () => onChanged(c),
        child: Container(
          width: 28, height: 28, margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: _tryParseColor(c), shape: BoxShape.circle,
            border: currentColor == c ? Border.all(color: Colors.white, width: 2) : null,
          ),
        ),
      )),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: () => _showColorPickerDialog(context, currentColor, onChanged),
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey, width: 1.5),
            color: _tryParseColor(currentColor),
          ),
          child: const Icon(Icons.colorize, size: 14, color: Colors.white),
        ),
      ),
    ]));
  }

  void _showColorPickerDialog(BuildContext context, String currentColor, ValueChanged<String> onChanged) {
    Color selected = _tryParseColor(currentColor);
    final hsv = HSVColor.fromColor(selected);
    double hue = hsv.hue;
    double sat = hsv.saturation;
    double bright = hsv.value;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('选择颜色'),
          content: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Preview
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: HSVColor.fromAHSV(1, hue, sat, bright).toColor(),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 16),
              // Hue
              Text('色调', style: TextStyle(fontSize: 12, color: Theme.of(ctx).brightness == Brightness.dark ? Colors.white70 : Colors.black54)),
              const SizedBox(height: 4),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000)]),
                    ),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 24,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      overlayColor: Colors.transparent,
                    ),
                    child: Slider(value: hue, min: 0, max: 360, onChanged: (v) => setDialogState(() => hue = v)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Saturation
              Row(children: [
                Text('饱和度', style: TextStyle(fontSize: 12, color: Theme.of(ctx).brightness == Brightness.dark ? Colors.white70 : Colors.black54)),
                Expanded(child: Slider(value: sat, min: 0, max: 1, onChanged: (v) => setDialogState(() => sat = v))),
              ]),
              // Brightness
              Row(children: [
                Text('亮度', style: TextStyle(fontSize: 12, color: Theme.of(ctx).brightness == Brightness.dark ? Colors.white70 : Colors.black54)),
                Expanded(child: Slider(value: bright, min: 0, max: 1, onChanged: (v) => setDialogState(() => bright = v))),
              ]),
              const SizedBox(height: 8),
              // Hex display
              Row(children: [
                Text('HEX:', style: TextStyle(fontSize: 12, color: Theme.of(ctx).brightness == Brightness.dark ? Colors.white70 : Colors.black54)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_hexFromHSV(HSVColor.fromAHSV(1, hue, sat, bright)), style: TextStyle(fontSize: 13, fontFamily: 'monospace')),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () {
              final hex = _hexFromHSV(HSVColor.fromAHSV(1, hue, sat, bright));
              Navigator.pop(ctx);
              onChanged(hex);
            }, child: const Text('确定')),
          ],
        ),
      ),
    );
  }

  String _hexFromHSV(HSVColor hsv) {
    final c = hsv.toColor();
    return '#${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  Color _tryParseColor(String hex) {
    try {
      if (hex.isEmpty) return const Color(0xFFFF0000);
      return Color(int.parse(hex.replaceFirst('#', '0xff')));
    } catch (_) {
      return const Color(0xFFFF0000);
    }
  }

  // ── Delete Confirmation ──

  void _confirmDelete(BuildContext context, String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除预算"$name"吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _api.dio.delete('/finance/budgets/$id');
                if (ctx.mounted) Navigator.pop(ctx);
                _consumptionCache.remove(id);
                ref.read(financeBudgetProvider.notifier).load();
                _loadSummary();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除成功')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
                }
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ── Budget Summary Card ──

  Widget _buildSummaryCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_summary == null) return const SizedBox.shrink();

    final total = (_summary!['total_budget'] as num?)?.toDouble() ?? 0;
    final used = (_summary!['total_used'] as num?)?.toDouble() ?? 0;
    final unallocated = (_summary!['unallocated'] as num?)?.toDouble() ?? 0;
    final uncategorized = (_summary!['uncategorized_used'] as num?)?.toDouble() ?? 0;
    final items = (_summary!['items'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Material(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Text('预算总览', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                const Spacer(),
                Text('总额 \u{FFE5}${_fmt(total)}', style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                const SizedBox(width: 8),
                Icon(_summaryExpanded ? Icons.expand_less : Icons.expand_more, size: 18, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
              ]),
              const SizedBox(height: 12),
              _buildBudgetBar(used, total, AppTheme.accent, isDark, height: 44),
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 4, children: [
                ...items.take(6).map<Widget>((item) {
                  final color = _parseColor(item['color'] as String? ?? '#4F46E5');
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 16, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 4),
                    Text('${item['name']}', style: TextStyle(fontSize: 8, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                  ]);
                }),
                if (unallocated > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 16, height: 3, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 4),
                    Text('未分配', style: TextStyle(fontSize: 8, color: Colors.grey)),
                  ]),
              ]),
              if (_summaryExpanded) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                ...items.map((item) {
                  final bgt = (item['budget'] as num?)?.toDouble() ?? 0;
                  final usd = (item['used'] as num?)?.toDouble() ?? 0;
                  final color = _parseColor(item['color'] as String? ?? '#4F46E5');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('${item['name']}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                        const Spacer(),
                        Text('已用 \u{FFE5}${_fmt(usd)} · 剩余 \u{FFE5}${_fmt(bgt - usd)}', style: TextStyle(fontSize: 9, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                      ]),
                      const SizedBox(height: 4),
                      _buildBudgetBar(usd, bgt, color, isDark),
                    ]),
                  );
                }),
                if (unallocated > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [
                        Text('未分配预算', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey)),
                        Spacer(),
                        Text('\u{FFE5}0', style: TextStyle(fontSize: 9, color: Colors.grey)),
                      ]),
                      const SizedBox(height: 4),
                      Container(height: 28, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300, width: 1), color: Colors.grey.shade50.withAlpha(100))),
                    ]),
                  ),
                if (uncategorized > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Text('未归类支出', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey)),
                        const Spacer(),
                        Text('\u{FFE5}${_fmt(uncategorized)}', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                      ]),
                      const SizedBox(height: 4),
                      _buildBudgetBar(uncategorized, uncategorized, Colors.grey, isDark),
                    ]),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildBudgetBar(double used, double total, Color color, bool isDark, {double height = 28}) {
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return Container(
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(height / 3), color: color.withAlpha(isDark ? 20 : 15)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          return Stack(children: [
            if (ratio > 0)
              Positioned(
                left: 0, top: 0, bottom: 0,
                width: maxW * ratio,
                child: CustomPaint(
                  painter: _BarCheckerPainter(baseColor: const Color(0xFFD4D4DC)),
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned(
              left: 0, top: 0, bottom: 0, right: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height / 3),
                  gradient: LinearGradient(colors: [color.withAlpha(0), color.withAlpha(80)]),
                ),
              ),
            ),
            if (ratio > 0.12)
              Positioned(left: 10, top: 0, bottom: 0, child: Align(alignment: Alignment.centerLeft, child: Text('\u{FFE5}${_fmt(used)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF6B6B8A))))),
            Positioned(right: 10, top: 0, bottom: 0, child: Align(alignment: Alignment.centerRight, child: Text('剩余 \u{FFE5}${_fmt(total - used)}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: ratio > 0.7 ? Colors.white : (isDark ? AppTheme.darkText : AppTheme.lightText))))),
          ]);
        },
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xff')));
    } catch (_) {
      return AppTheme.accent;
    }
  }
}

// ── Checkerboard Pattern (Photoshop canvas texture — spent budget indicator) ──
class _CheckerboardPainter extends CustomPainter {
  final bool isDark;
  _CheckerboardPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final light = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.20)
          : Colors.white.withValues(alpha: 0.45);
    final dark = Paint()
      ..color = isDark
          ? Colors.black.withValues(alpha: 0.45)
          : Colors.black.withValues(alpha: 0.35);
    const grid = 6.0;
    final cols = (size.width / grid).ceil();
    final rows = (size.height / grid).ceil();
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final rect = Rect.fromLTWH(col * grid, row * grid, grid, grid);
        canvas.drawRect(rect, (row + col) % 2 == 0 ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter old) => old.isDark != isDark;
}

// ── Budget Bar Checker Pattern (diagonal cross-hatch on solid background) ──
class _BarCheckerPainter extends CustomPainter {
  final Color baseColor;
  _BarCheckerPainter({this.baseColor = const Color(0xFFD4D4DC)});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = baseColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    final linePaint = Paint()
      ..color = const Color(0x0F000000)
      ..strokeWidth = 0.5;

    const double cellSize = 4;
    for (double x = 0; x < size.width; x += cellSize * 2) {
      for (double y = 0; y < size.height; y += cellSize * 2) {
        canvas.drawLine(Offset(x + cellSize, y), Offset(x, y + cellSize), linePaint);
        canvas.drawLine(Offset(x, y), Offset(x + cellSize, y + cellSize), linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
