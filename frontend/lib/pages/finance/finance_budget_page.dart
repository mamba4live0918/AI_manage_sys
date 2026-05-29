import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    Future.microtask(() => ref.read(financeBudgetProvider.notifier).load());
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
                  onRefresh: () async => ref.read(financeBudgetProvider.notifier).load(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                    itemCount: state.items.length,
                    itemBuilder: (_, i) => _buildBudgetCard(context, state.items[i]),
                  ),
                ),
    );
  }

  Widget _buildBudgetCard(BuildContext context, BudgetData b) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pct = b.totalAmount > 0 ? (b.usedAmount / b.totalAmount).clamp(0.0, 1.0) : 0.0;
    final statusLabel = _statusLabels[b.status] ?? b.status;
    final statusColor = _statusColors[b.status] ?? Colors.grey;
    final warnColor = pct > 0.9 ? Colors.red : pct > 0.7 ? Colors.orange : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showBudgetDetail(context, b),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: name + status + menu
              Row(children: [
                Expanded(
                  child: Row(children: [
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
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 20), SizedBox(width: 8), Text('编辑')])),
                    const PopupMenuItem(value: 'adjust', child: Row(children: [Icon(Icons.tune, size: 20), SizedBox(width: 8), Text('调整')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 20), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                  ],
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
    final warnColor = pct > 0.9 ? Colors.red : pct > 0.7 ? Colors.orange : Colors.green;

    if (items.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct,
          minHeight: 10,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation(warnColor),
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
            if (items.isEmpty && b.totalAmount <= 0) return Container(color: Colors.grey.shade200);
            final sorted = List<BudgetItemData>.from(items)
              ..sort((a, b) => b.amount.compareTo(a.amount));
            final segments = <Widget>[];
            double usedW = 0;
            for (final item in sorted) {
              final segW = (item.amount / displayTotal) * totalW;
              if (segW < 2) continue;
              usedW += segW;
              final fillRatio = item.amount > 0 ? (item.usedAmount / item.amount).clamp(0.0, 1.0) : 0.0;
              final fillW = segW * fillRatio;
              final color = _itemColor(item);
              segments.add(SizedBox(
                width: segW,
                child: Row(children: [
                  if (fillW >= 1)
                    SizedBox(width: fillW, child: Container(color: color)),
                  if (segW - fillW >= 1)
                    SizedBox(width: segW - fillW, child: Container(color: color.withAlpha(40))),
                ]),
              ));
            }
            // Unallocated amount in grey
            final unallocated = b.totalAmount - itemSum;
            if (unallocated > 0 && totalW - usedW >= 2) {
              segments.add(SizedBox(width: totalW - usedW, child: Container(color: Colors.grey.shade400)));
            }
            if (segments.isEmpty) return Container(color: Colors.grey.shade200);
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
    if (val.abs() >= 10000) return '¥${(val / 10000).toStringAsFixed(1)}万';
    return '¥${val.toStringAsFixed(0)}';
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
                final warnColor = pct > 0.9 ? Colors.red : pct > 0.7 ? Colors.orange : Colors.green;
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
                        // Progress
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 14,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(warnColor),
                          ),
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
                    _sectionTitle('预算项目详情', textColor),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    else if (b.items.isEmpty)
                      _emptyHint('暂无预算项目', isDark)
                    else
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
                                  child: LinearProgressIndicator(
                                    value: usedPct / 100,
                                    minHeight: 6,
                                    backgroundColor: catColor.withValues(alpha: 0.12),
                                    valueColor: AlwaysStoppedAnimation(catColor),
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
                          const Divider(height: 20),
                          Row(children: [
                            Text('预算总额', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                            const Spacer(),
                            Text(_fmt(b.totalAmount), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                          ]),
                        ]),
                      ),
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
    return Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color));
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
      if (c.isEmpty || c == '#FF0000') return const Color(0xFFFF0000);
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

  // ── Create Dialog ──

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: '2026');
    final quarterCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? selectedProjectId;
    String selectedStatus = 'active';
    // Line items: list of {category, nameCtrl, amountCtrl}
    final List<Map<String, dynamic>> items = [
      _newItemEntry('other', '', '0'),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final itemTotal = items.fold<double>(0, (s, item) {
            final amt = double.tryParse((item['amountCtrl'] as TextEditingController).text) ?? 0;
            return s + amt;
          });

          return AlertDialog(
            title: const Text('创建预算'),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '预算名称')),
                  TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: '年度'), keyboardType: TextInputType.number),
                  TextField(controller: quarterCtrl, decoration: const InputDecoration(labelText: '季度 (1-4, 留空=全年)'), keyboardType: TextInputType.number),
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
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: '备注说明'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(labelText: '状态'),
                    items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDialogState(() => selectedStatus = v ?? 'active'),
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
                  final data = <String, dynamic>{
                    'name': nameCtrl.text,
                    'year': int.tryParse(yearCtrl.text) ?? 2026,
                    'quarter': quarter,
                    'status': selectedStatus,
                    'items': itemsList,
                  };
                  if (selectedProjectId != null) data['project_id'] = selectedProjectId;
                  if (notesCtrl.text.isNotEmpty) data['notes'] = notesCtrl.text;
                  await _api.dio.post('/finance/budgets', data: data);
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.read(financeBudgetProvider.notifier).load();
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
}
