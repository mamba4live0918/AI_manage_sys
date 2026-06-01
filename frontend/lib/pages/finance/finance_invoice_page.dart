import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/finance_providers.dart';
import '../../config/theme.dart';
import '../../models/finance_models.dart';
import '../../services/api_client.dart';
import '../../widgets/budget_tree_selector.dart';
class FinanceInvoicePage extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const FinanceInvoicePage({super.key, this.onBack});

  @override
  ConsumerState<FinanceInvoicePage> createState() => _FinanceInvoicePageState();
}

class _FinanceInvoicePageState extends ConsumerState<FinanceInvoicePage> {
  final ApiClient _api = ApiClient();
  String _selectedStatus = '';
  final Map<String, List<PaymentData>> _paymentsCache = {};
  final Map<String, double> _paymentTotals = {};
  final Map<String, List<Map<String, dynamic>>> _voucherCache = {};
  bool _loadingPayments = false;
  List<Map<String, dynamic>> _projectList = [];
  bool _projectsLoaded = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _page = 0;
  static const int _pageSize = 20;

  List<InvoiceData> get _pagedItems {
    final items = ref.read(financeInvoiceProvider).items;
    final start = _page * _pageSize;
    final end = start + _pageSize;
    if (start >= items.length) return [];
    return items.sublist(start, end > items.length ? items.length : end);
  }

  int get _totalPages {
    final len = ref.read(financeInvoiceProvider).items.length;
    if (len == 0) return 0;
    return (len / _pageSize).ceil();
  }

  static const _statusOptions = ['', 'issued', 'partial', 'paid', 'cancelled'];
  static const _statusLabels = {
    '': '全部',
    'issued': '已开票',
    'partial': '部分收款',
    'paid': '已收款',
    'cancelled': '已取消',
  };
  static const _statusColors = {
    'issued': Colors.orange,
    'partial': Colors.blue,
    'paid': Colors.green,
    'cancelled': Colors.grey,
  };
  static const _paymentMethodLabels = {
    'bank_transfer': '银行转账',
    'cash': '现金',
    'cheque': '支票',
    'other': '其他',
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(financeInvoiceProvider.notifier).load();
      _loadAllPayments();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllPayments() async {
    if (_loadingPayments) return;
    setState(() => _loadingPayments = true);
    try {
      final resp = await _api.dio.get('/finance/payments',
          queryParameters: {'limit': '1000'});
      final payments = (resp.data['items'] as List)
          .map((j) => PaymentData.fromJson(j))
          .toList();
      _paymentTotals.clear();
      _paymentsCache.clear();
      for (final p in payments) {
        if (p.invoiceId != null) {
          _paymentTotals[p.invoiceId!] =
              (_paymentTotals[p.invoiceId!] ?? 0) + p.amount;
          _paymentsCache.putIfAbsent(p.invoiceId!, () => []).add(p);
        }
      }
      // Also load vouchers
      final vResp = await _api.dio.get('/finance/vouchers',
          queryParameters: {'limit': '1000'});
      final vouchers = List<Map<String, dynamic>>.from(vResp.data['items']);
      _voucherCache.clear();
      for (final v in vouchers) {
        final invId = v['invoice_id'] as String?;
        if (invId != null) {
          _voucherCache.putIfAbsent(invId, () => []).add(v);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingPayments = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeInvoiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('票据管理'),
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Breadcrumb
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              Text('首页', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: Colors.grey))),
              Text('财务', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: Colors.grey))),
              Text('票据管理', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索发票号、销售方或购买方名称',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _page = 0;
                        });
                        ref.read(financeInvoiceProvider.notifier).load(status: _selectedStatus);
                      })
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (v) {
                setState(() => _searchQuery = v);
              },
              onSubmitted: (v) {
                setState(() => _page = 0);
                ref.read(financeInvoiceProvider.notifier).load(status: _selectedStatus, search: v);
              },
            ),
          ),
          _buildFilterBar(theme, isDark),
          const Divider(height: 1),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.items.isEmpty
                    ? _buildEmptyState(theme)
                    : Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1.4),  // 编号
                                  1: FlexColumnWidth(1.8),  // 金额(含已收)
                                  2: FlexColumnWidth(1.6),  // 销售方
                                  3: FlexColumnWidth(1.6),  // 购买方
                                  4: FlexColumnWidth(1.2),  // 到期日
                                  5: FlexColumnWidth(1.0),  // 状态
                                },
                                border: TableBorder(
                                  horizontalInside: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 0.5),
                                ),
                                children: [
                                  // Header row
                                  TableRow(
                                    decoration: BoxDecoration(
                                      color: isDark ? AppTheme.darkSurfaceAlt : const Color(0xFFF5F5FA),
                                    ),
                                    children: const [
                                      _TableHeader('编号'),
                                      _TableHeader('金额'),
                                      _TableHeader('销售方'),
                                      _TableHeader('购买方'),
                                      _TableHeader('到期日'),
                                      _TableHeader('状态'),
                                      _TableHeader('操作'),
                                    ],
                                  ),
                                  // Data rows
                                  ..._pagedItems.map((inv) {
                                    final paid = _paymentTotals[inv.id] ?? 0;
                                    final total = inv.amount;
                                    final remaining = total - paid;
                                    return TableRow(
                                      children: [
                                        _TableCell(
                                          Text(inv.invoiceNo.isNotEmpty ? inv.invoiceNo : '—',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.accentLight : AppTheme.accent)),
                                          isDark: isDark, onTap: () => _showDetailSheet(context, inv),
                                        ),
                                        _TableCell(
                                          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                            Text('\u{FFE5}${inv.amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                                            if (paid > 0 && paid < total)
                                              Text('已收 \u{FFE5}${paid.toStringAsFixed(0)}', style: TextStyle(fontSize: 10, color: AppTheme.green)),
                                            if (paid >= total && total > 0)
                                              Text('已收 \u{FFE5}${paid.toStringAsFixed(0)}', style: TextStyle(fontSize: 10, color: AppTheme.green)),
                                          ]),
                                          isDark: isDark, onTap: () => _showDetailSheet(context, inv),
                                        ),
                                        _TableCell(
                                          Text(inv.sellerName.isNotEmpty ? inv.sellerName : '—', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                                          isDark: isDark, onTap: () => _showDetailSheet(context, inv),
                                        ),
                                        _TableCell(
                                          Text(inv.buyerName.isNotEmpty ? inv.buyerName : '—', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                                          isDark: isDark, onTap: () => _showDetailSheet(context, inv),
                                        ),
                                        _TableCell(
                                          Text(inv.dueDate != null && inv.dueDate!.length >= 10 ? inv.dueDate!.substring(0, 10) : '—', style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                                          isDark: isDark, onTap: () => _showDetailSheet(context, inv),
                                        ),
                                        _TableCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: (_statusColors[inv.status] ?? Colors.grey).withAlpha(isDark ? 30 : 20),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(_statusLabels[inv.status] ?? inv.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _statusColors[inv.status] ?? Colors.grey)),
                                          ),
                                          isDark: isDark, onTap: () => _showDetailSheet(context, inv),
                                        ),
                                        _InvoiceActionCell(
                                          invoiceId: inv.id,
                                          status: inv.status,
                                          remaining: remaining,
                                          isDark: isDark,
                                          onPay: () => _showPaymentDialog(context, inv.id, total, paid),
                                          onDetail: () => _showDetailSheet(context, inv),
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          if (_totalPages > 1)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                IconButton(
                                  icon: const Icon(Icons.chevron_left, size: 20),
                                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                                ),
                                Text('${_page + 1} / $_totalPages',
                                  style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                                IconButton(
                                  icon: const Icon(Icons.chevron_right, size: 20),
                                  onPressed: _page < _totalPages - 1 ? () => setState(() => _page++) : null,
                                ),
                              ]),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isDark ? Colors.white10 : theme.colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusOptions.map((s) {
            final selected = _selectedStatus == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  _statusLabels[s]!,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected
                        ? Colors.white
                        : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                selected: selected,
                selectedColor: theme.colorScheme.primary,
                backgroundColor:
                    isDark ? Colors.white12 : Colors.grey.shade200,
                side: BorderSide.none,
                onSelected: (v) {
                  if (v) {
                    setState(() {
                      _selectedStatus = s;
                      _page = 0;
                    });
                    ref
                        .read(financeInvoiceProvider.notifier)
                        .load(status: s);
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            '暂无发票',
            style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('创建第一张发票'),
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
    );
  }

  // ─── Invoice card with progress bar and quick payment ───

  Widget _buildInvoiceCard(InvoiceData inv, bool isDark, ThemeData theme) {
    final paid = _paymentTotals[inv.id] ?? 0;
    final total = inv.amount;
    final ratio = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
    final pct = (ratio * 100);
    final isFullyPaid = inv.status == 'paid' || paid >= total;
    final isPartial = paid > 0 && !isFullyPaid;

    Color progressColor;
    if (isFullyPaid) {
      progressColor = Colors.green;
    } else if (isPartial) {
      progressColor = Colors.blue;
    } else {
      progressColor = Colors.orange;
    }

    final statusColor =
        (_statusColors[inv.status] ?? Colors.grey).withValues(alpha: isDark ? 0.9 : 1);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetailSheet(context, inv),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: invoice_no + status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inv.invoiceNo.isNotEmpty ? inv.invoiceNo : '无发票号',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusLabels[inv.status] ?? inv.status,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (inv.buyerName.isNotEmpty || inv.sellerName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${inv.sellerName.isNotEmpty ? '${inv.sellerName} → ' : ''}${inv.buyerName.isNotEmpty ? inv.buyerName : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              if (inv.projectId != null && inv.projectId!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '关联项目: ${inv.projectId}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor:
                      isDark ? Colors.white12 : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
              const SizedBox(height: 8),
              // Progress text + quick action + more menu
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '已收 \u{FFE5}${paid.toStringAsFixed(2)} / \u{FFE5}${total.toStringAsFixed(2)} (${pct.toStringAsFixed(0)}%)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ),
                  if (!isFullyPaid)
                    TextButton.icon(
                      onPressed: () =>
                          _showPaymentDialog(context, inv.id, total, paid),
                      icon: const Icon(Icons.attach_money, size: 16),
                      label:
                          const Text('收款', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (v) {
                      if (v == 'delete') _confirmDelete(context, inv.id);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('删除'),
                        ]),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadProjects() async {
    if (_projectsLoaded) return;
    try {
      final resp = await _api.dio.get('/pm/projects', queryParameters: {'limit': '200'});
      _projectList = List<Map<String, dynamic>>.from(resp.data['items'] ?? []);
      _projectsLoaded = true;
    } catch (_) {}
  }

  // ─── Create dialog ───

  void _showCreateDialog(BuildContext context) {
    final invoiceNoCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final taxAmountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final projectIdCtrl = TextEditingController();
    final sellerNameCtrl = TextEditingController();
    final sellerTaxIdCtrl = TextEditingController();
    final buyerNameCtrl = TextEditingController();
    final buyerTaxIdCtrl = TextEditingController();
    final taxRateCtrl = TextEditingController(text: '0.13');
    String? issueDate;
    String? dueDate;
    String? errorMsg;
    String? selectedBudgetId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('创建发票'),
          content: SizedBox(width: 500, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                    ]),
                  ),
                ),
              TextField(
                  controller: invoiceNoCtrl,
                  decoration: const InputDecoration(labelText: '发票号')),
              const SizedBox(height: 8),
              TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: '金额'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: taxAmountCtrl,
                  decoration: const InputDecoration(labelText: '税额'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: taxRateCtrl,
                  decoration: const InputDecoration(
                      labelText: '税率', helperText: '默认 0.13 即 13%'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 8),
              FutureBuilder(
                future: _loadProjects(),
                builder: (_, __) => Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (p) => p['name'] as String? ?? '',
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) return _projectList;
                    return _projectList.where((p) =>
                      (p['name'] as String? ?? '').toLowerCase().contains(textEditingValue.text.toLowerCase())
                    ).toList();
                  },
                  onSelected: (p) {
                    projectIdCtrl.text = p['id'] as String? ?? '';
                  },
                  fieldViewBuilder: (ctx, ctrl, node, _) => TextField(
                    controller: ctrl,
                    focusNode: node,
                    decoration: InputDecoration(
                      labelText: '关联项目',
                      hintText: '搜索并选择项目',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: Text(issueDate == null
                        ? '开票日期: 未设置'
                        : '开票日期: $issueDate')),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) {
                      setDialogState(() =>
                          issueDate = d.toIso8601String().substring(0, 10));
                    }
                  },
                  child: const Text('选择'),
                ),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                    child: Text(dueDate == null
                        ? '到期日期: 未设置'
                        : '到期日期: $dueDate')),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate:
                          DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) {
                      setDialogState(() =>
                          dueDate = d.toIso8601String().substring(0, 10));
                    }
                  },
                  child: const Text('选择'),
                ),
              ]),
              const SizedBox(height: 8),
              BudgetTreeSelector(
                label: '关联预算 (可选)',
                onChanged: (v) => setDialogState(() => selectedBudgetId = v),
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: '备注'),
                  maxLines: 2),
              const SizedBox(height: 8),
              TextField(
                  controller: sellerNameCtrl,
                  decoration: const InputDecoration(labelText: '销售方名称')),
              const SizedBox(height: 8),
              TextField(
                  controller: sellerTaxIdCtrl,
                  decoration: const InputDecoration(labelText: '销售方税号')),
              const SizedBox(height: 8),
              TextField(
                  controller: buyerNameCtrl,
                  decoration: const InputDecoration(labelText: '购买方名称')),
              const SizedBox(height: 8),
              TextField(
                  controller: buyerTaxIdCtrl,
                  decoration: const InputDecoration(labelText: '购买方税号')),
            ]),
          )),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
                onPressed: () async {
                  try {
                    final body = <String, dynamic>{
                      'invoice_no': invoiceNoCtrl.text,
                      'amount': double.tryParse(amountCtrl.text) ?? 0,
                      'tax_amount':
                          double.tryParse(taxAmountCtrl.text) ?? 0,
                      'tax_rate':
                          double.tryParse(taxRateCtrl.text) ?? 0.13,
                      'notes': notesCtrl.text,
                      'seller_name': sellerNameCtrl.text,
                      'seller_tax_id': sellerTaxIdCtrl.text,
                      'buyer_name': buyerNameCtrl.text,
                      'buyer_tax_id': buyerTaxIdCtrl.text,
                      'status': 'issued',
                    };
                    if (selectedBudgetId != null) {
                      body['budget_id'] = selectedBudgetId;
                    }
                    if (projectIdCtrl.text.isNotEmpty) {
                      body['project_id'] = projectIdCtrl.text;
                    }
                    if (issueDate != null) body['issue_date'] = issueDate;
                    if (dueDate != null) body['due_date'] = dueDate;
                    await _api.dio
                        .post('/finance/invoices', data: body);
                    if (ctx.mounted) Navigator.pop(ctx);
                    ref
                        .read(financeInvoiceProvider.notifier)
                        .load(status: _selectedStatus);
                  } catch (e) {
                    setDialogState(() => errorMsg = '创建失败: $e');
                  }
                },
                child: const Text('创建')),
          ],
        ),
      ),
    );
  }

  // ─── Detail sheet ───

  void _showDetailSheet(BuildContext context, InvoiceData inv) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        bool isEditing = false;
        String? errorMsg;
        final editInvoiceNoCtrl =
            TextEditingController(text: inv.invoiceNo);
        final editAmountCtrl =
            TextEditingController(text: inv.amount.toStringAsFixed(2));
        final editTaxAmountCtrl =
            TextEditingController(text: inv.taxAmount.toStringAsFixed(2));
        final editNotesCtrl = TextEditingController(text: inv.notes);
        final editSellerNameCtrl = TextEditingController(text: inv.sellerName);
        final editSellerTaxIdCtrl = TextEditingController(text: inv.sellerTaxId);
        final editBuyerNameCtrl = TextEditingController(text: inv.buyerName);
        final editBuyerTaxIdCtrl = TextEditingController(text: inv.buyerTaxId);

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final payments = _paymentsCache[inv.id] ?? [];
            final loadingPaymentsLocal =
                _loadingPayments && !_paymentsCache.containsKey(inv.id);

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                          child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade400,
                                  borderRadius:
                                      BorderRadius.circular(2)))),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: Text('发票详情',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: textColor))),
                        if (isEditing)
                          TextButton(
                            onPressed: () => setSheetState(() => isEditing = false),
                            child: const Text('取消编辑'),
                          )
                        else if (!inv.status.startsWith('partial') && inv.status != 'paid' && inv.status != 'cancelled')
                          TextButton.icon(
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('编辑'),
                            onPressed: () => setSheetState(() => isEditing = true),
                          ),
                      ]),
                      const SizedBox(height: 16),

                      if (isEditing) ...[
                        if (errorMsg != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                              ]),
                            ),
                          ),
                        TextField(
                            controller: editInvoiceNoCtrl,
                            decoration:
                                const InputDecoration(labelText: '发票号'),
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: editAmountCtrl,
                            decoration:
                                const InputDecoration(labelText: '金额'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: editTaxAmountCtrl,
                            decoration:
                                const InputDecoration(labelText: '税额'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: editNotesCtrl,
                            decoration:
                                const InputDecoration(labelText: '备注'),
                            maxLines: 2,
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: editSellerNameCtrl,
                            decoration:
                                const InputDecoration(labelText: '销售方名称'),
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: editSellerTaxIdCtrl,
                            decoration:
                                const InputDecoration(labelText: '销售方税号'),
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: editBuyerNameCtrl,
                            decoration:
                                const InputDecoration(labelText: '购买方名称'),
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 8),
                        TextField(
                            controller: editBuyerTaxIdCtrl,
                            decoration:
                                const InputDecoration(labelText: '购买方税号'),
                            style: TextStyle(color: textColor)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () async {
                              try {
                                await _api.dio.put(
                                    '/finance/invoices/${inv.id}',
                                    data: {
                                      'invoice_no':
                                          editInvoiceNoCtrl.text,
                                      'amount':
                                          double.tryParse(
                                                  editAmountCtrl.text) ??
                                              inv.amount,
                                      'tax_amount':
                                          double.tryParse(
                                                  editTaxAmountCtrl.text) ??
                                              inv.taxAmount,
                                      'notes': editNotesCtrl.text,
                                      'seller_name': editSellerNameCtrl.text,
                                      'seller_tax_id': editSellerTaxIdCtrl.text,
                                      'buyer_name': editBuyerNameCtrl.text,
                                      'buyer_tax_id': editBuyerTaxIdCtrl.text,
                                    });
                                if (ctx.mounted) Navigator.pop(ctx);
                                ref
                                    .read(financeInvoiceProvider.notifier)
                                    .load(status: _selectedStatus);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('发票更新成功')));
                                }
                              } catch (e) {
                                setSheetState(() => errorMsg = '更新失败: $e');
                              }
                            },
                            child: const Text('保存修改'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        _detailRow(
                            '发票号',
                            inv.invoiceNo.isNotEmpty ? inv.invoiceNo : '无',
                            labelColor,
                            textColor),
                        _detailRow('金额',
                            '\u{FFE5}${inv.amount.toStringAsFixed(2)}',
                            labelColor, textColor),
                        _detailRow('税额',
                            '\u{FFE5}${inv.taxAmount.toStringAsFixed(2)}',
                            labelColor, textColor),
                        _detailRow(
                            '税率',
                            '${(inv.taxRate * 100).toStringAsFixed(0)}%',
                            labelColor,
                            textColor),
                        _detailRow('开票日期',
                            inv.issueDate ?? '未设置', labelColor, textColor),
                        _detailRow('到期日期',
                            inv.dueDate ?? '未设置', labelColor, textColor),
                        _detailRow(
                            '备注',
                            inv.notes.isNotEmpty ? inv.notes : '无',
                            labelColor,
                            textColor),
                        _detailRow(
                            '销售方名称',
                            inv.sellerName.isNotEmpty ? inv.sellerName : '无',
                            labelColor,
                            textColor),
                        _detailRow(
                            '销售方税号',
                            inv.sellerTaxId.isNotEmpty ? inv.sellerTaxId : '无',
                            labelColor,
                            textColor),
                        _detailRow(
                            '购买方名称',
                            inv.buyerName.isNotEmpty ? inv.buyerName : '无',
                            labelColor,
                            textColor),
                        _detailRow(
                            '购买方税号',
                            inv.buyerTaxId.isNotEmpty ? inv.buyerTaxId : '无',
                            labelColor,
                            textColor),
                        if (inv.createdAt != null)
                          _detailRow(
                              '创建时间', inv.createdAt!, labelColor, textColor),
                        Row(children: [
                          Text('状态', style: TextStyle(color: labelColor, fontSize: 14)),
                          const SizedBox(width: 12),
                          Chip(
                            label: Text(_statusLabels[inv.status] ?? inv.status, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            backgroundColor: (_statusColors[inv.status] ?? Colors.grey),
                          ),
                        ]),
                        const SizedBox(height: 24),
                      ],

                      // Payments section
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text('收款记录',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textColor)),
                      ]),
                      if (loadingPaymentsLocal)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator()))
                      else if (payments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                              child: Text('暂无收款记录',
                                  style: TextStyle(
                                      color: labelColor, fontSize: 14))),
                        )
                      else
                        ...payments.map((p) => Material(
                              color: isDark ? Colors.white10 : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showPaymentDetail(ctx, p),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Text(
                                              '\u{FFE5}${p.amount.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: textColor)),
                                          const Spacer(),
                                          Chip(
                                            label: Text(
                                                _paymentMethodLabels[
                                                        p.paymentMethod] ??
                                                    p.paymentMethod,
                                                style: const TextStyle(
                                                    fontSize: 11)),
                                            backgroundColor: isDark
                                                ? Colors.white12
                                                : Colors.grey.shade200,
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.chevron_right,
                                              size: 18, color: Colors.grey),
                                        ]),
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          if (p.paymentDate != null) ...[
                                            Icon(Icons.calendar_today,
                                                size: 14, color: labelColor),
                                            const SizedBox(width: 4),
                                            Text(p.paymentDate!,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color: labelColor)),
                                            const SizedBox(width: 16),
                                          ],
                                          if (p.refNo.isNotEmpty) ...[
                                            Icon(Icons.tag,
                                                size: 14, color: labelColor),
                                            const SizedBox(width: 4),
                                            Expanded(
                                                child: Text(p.refNo,
                                                    style: TextStyle(
                                                        fontSize: 13,
                                                        color: labelColor),
                                                    overflow: TextOverflow
                                                        .ellipsis)),
                                          ],
                                        ]),
                                        if (p.notes.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(p.notes,
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    color: labelColor)),
                                          ),
                                      ]),
                                ),
                              ),
                            )),

                      // Vouchers section
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      Builder(builder: (_) {
                        final vouchers = _voucherCache[inv.id] ?? [];
                        final voucherTheme = Theme.of(ctx);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Text('凭证',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: textColor)),
                              if (vouchers.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: voucherTheme.colorScheme.primary
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${vouchers.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: voucherTheme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ]),
                            if (vouchers.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                    child: Text('暂无凭证',
                                        style: TextStyle(
                                            color: labelColor,
                                            fontSize: 14))),
                              )
                            else
                              ...vouchers.map((v) => _buildVoucherItem(
                                  v, isDark, textColor, labelColor, ctx)),
                          ],
                        );
                      }),
                    ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(
      String label, String value, Color labelColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(color: labelColor, fontSize: 14))),
        Expanded(
            child: Text(value,
                style: TextStyle(color: textColor, fontSize: 14))),
      ]),
    );
  }

  // ─── Payment detail popup ───

  void _showPaymentDetail(BuildContext context, PaymentData p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('收款详情', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 20),
            _detailRow('金额', '\u{FFE5}${p.amount.toStringAsFixed(2)}', labelColor, textColor),
            _detailRow('日期', p.paymentDate ?? '未设置', labelColor, textColor),
            _detailRow('方式', _paymentMethodLabels[p.paymentMethod] ?? p.paymentMethod, labelColor, textColor),
            _detailRow('流水号', p.refNo.isNotEmpty ? p.refNo : '无', labelColor, textColor),
            _detailRow('备注', p.notes.isNotEmpty ? p.notes : '无', labelColor, textColor),
            // Vouchers for this invoice
            Builder(builder: (_) {
              final vouchers = p.invoiceId != null ? (_voucherCache[p.invoiceId!] ?? []) : <Map<String, dynamic>>[];
              if (vouchers.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Text('凭证 (${vouchers.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 8),
                ...vouchers.map((v) => _buildVoucherItem(v, isDark, textColor, labelColor, ctx)),
              ]);
            }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  // ─── Voucher item ───

  Widget _buildVoucherItem(Map<String, dynamic> v, bool isDark,
      Color textColor, Color labelColor, BuildContext ctx) {
    final typeLabels = {
      'invoice': '发票',
      'receipt': '收据',
      'contract': '合同',
      'other': '其他',
    };
    final voucherType =
        typeLabels[v['type']] ?? (v['type'] as String?) ?? '未知';
    final description = (v['description'] as String?) ?? '';
    final createdAt = (v['created_at'] as String?) ?? '';
    final fileId = v['file_id'] as String?;

    return Material(
      color: isDark ? Colors.white10 : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (fileId != null) {
            _downloadVoucher(context, v);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: fileId != null
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  fileId != null ? Icons.attach_file : Icons.description,
                  size: 20,
                  color: fileId != null ? Colors.blue : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          voucherType,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        if (fileId != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.visibility,
                              size: 13,
                              color: isDark
                                  ? Colors.white38
                                  : Colors.black38),
                        ],
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: labelColor,
                        ),
                      ),
                    ],
                    if (createdAt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 18, color: labelColor),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        _showEditVoucherDescriptionDialog(context, v),
                    tooltip: '编辑说明',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: Colors.red.shade300),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    onPressed: () => _confirmDeleteVoucher(context, v),
                    tooltip: '删除',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteVoucher(BuildContext context, Map<String, dynamic> v) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? errorMsg;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('确认删除'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('确定要删除此凭证吗？'),
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(errorMsg!,
                              style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 13))),
                    ]),
                  ),
                ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  try {
                    await _api.dio.delete('/finance/vouchers/${v['id']}');
                    Navigator.pop(ctx); // close confirm dialog
                    Navigator.of(context).pop(); // close detail sheet
                    await _loadAllPayments();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('凭证已删除')),
                      );
                    }
                  } catch (e) {
                    setDialogState(() => errorMsg = '删除失败: $e');
                  }
                },
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditVoucherDescriptionDialog(
      BuildContext context, Map<String, dynamic> v) {
    final descCtrl =
        TextEditingController(text: v['description'] as String? ?? '');
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑凭证说明'),
          content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: '说明'),
              maxLines: 3,
            ),
            if (errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(errorMsg!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13))),
                  ]),
                ),
              ),
          ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final newDesc = descCtrl.text.trim();
                try {
                  await _api.dio.put('/finance/vouchers/${v['id']}',
                      data: {'description': newDesc});
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadAllPayments();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('凭证说明已更新')),
                    );
                  }
                } catch (e) {
                  setDialogState(() => errorMsg = '更新失败: $e');
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      return iso.substring(0, 10);
    } catch (_) {
      return iso;
    }
  }

  void _downloadVoucher(BuildContext context, Map<String, dynamic> voucher) async {
    final fileId = voucher['file_id'] as String?;
    if (fileId == null) return;

    showDialog(context: context, barrierDismissible: false, useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()));

    String? fileUrl, fileName;
    try {
      final resp = await _api.dio.get('/preview/file/$fileId');
      fileUrl = resp.data['url'] as String?;
      fileName = resp.data['name'] as String?;
    } catch (_) {}

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    if (fileUrl == null || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取文件失败')));
      }
      return;
    }

    final desc = (voucher['description'] as String?) ?? '';

    showDialog(context: context, useRootNavigator: true, builder: (ctx) => AlertDialog(
      title: Text(desc.isNotEmpty ? desc : '下载凭证'),
      content: Text(fileName ?? '文件'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('下载'),
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              final dir = Directory.systemTemp;
              final savePath = '${dir.path}${Platform.pathSeparator}${fileName ?? 'file'}';
              // Use bare Dio without auth headers for external MinIO URLs
              await Dio().download(fileUrl!, savePath);
              await Process.run('cmd', ['/c', 'start', '', savePath]);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下载失败')));
              }
            }
          },
        ),
      ],
    ));
  }

  // ─── Payment dialog (reusable from card) ───

  void _showPaymentDialog(BuildContext context, String invoiceId,
      double invoiceAmount, double alreadyPaid) {
    final remaining = (invoiceAmount - alreadyPaid).clamp(0.0, double.infinity);
    final amountCtrl = TextEditingController();
    final refNoCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final voucherDescCtrl = TextEditingController();
    String selectedMethod = 'bank_transfer';
    String paymentDate = DateTime.now().toIso8601String().substring(0, 10);
    String? errorMsg;
    String? voucherFileName;
    Uint8List? voucherBytes;
    String? voucherError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加收款'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Remaining hint
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '剩余应收: \u{FFE5}${remaining.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue),
                    ),
                  ),
                  if (errorMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                      labelText: '收款金额',
                      hintText: '\u{FFE5}${remaining.toStringAsFixed(2)}',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  // Payment date
                  Row(children: [
                    Expanded(child: Text('收款日期: $paymentDate')),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) {
                          setDialogState(() =>
                              paymentDate =
                                  d.toIso8601String().substring(0, 10));
                        }
                      },
                      child: const Text('选择'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // Payment method
                  InputDecorator(
                    decoration: const InputDecoration(labelText: '收款方式'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedMethod,
                        isExpanded: true,
                        items: _paymentMethodLabels.entries
                            .map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() {
                              selectedMethod = v;
                              if (v == 'cash' || v == 'other') {
                                refNoCtrl.clear();
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  if (selectedMethod == 'bank_transfer' || selectedMethod == 'cheque') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: refNoCtrl,
                      decoration: InputDecoration(
                        labelText: selectedMethod == 'bank_transfer' ? '银行流水号（必填）' : '支票号码（必填）',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: '备注'),
                      maxLines: 2),

                  const SizedBox(height: 8),
                  if (selectedMethod == 'cash') ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text(
                        '现金收款无需上传凭证',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ]),
                  ] else ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.upload_file, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '上传凭证（必填）',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.attach_file, size: 16),
                        label: const Text('选择文件'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: voucherFileName != null
                              ? null
                              : Colors.red,
                          side: BorderSide(
                            color: voucherFileName != null
                                ? Theme.of(ctx).colorScheme.outline
                                : Colors.red,
                          ),
                        ),
                        onPressed: () async {
                          try {
                            final result = await FilePicker.platform
                                .pickFiles(withData: true);
                            if (result != null &&
                                result.files.isNotEmpty) {
                              final file = result.files.first;
                              setDialogState(() {
                                voucherFileName = file.name;
                                voucherBytes = file.bytes;
                              });
                            }
                          } catch (_) {}
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          voucherFileName ?? '未选择文件',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: voucherFileName != null
                                ? Theme.of(ctx).colorScheme.onSurface
                                : Theme.of(ctx)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ]),
                    if (selectedMethod == 'other') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: voucherDescCtrl,
                        decoration: const InputDecoration(
                          labelText: '凭证说明',
                          hintText: '其他方式必须填写凭证说明',
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            FilledButton(
                onPressed: () async {
                  final amountStr = amountCtrl.text.trim();
                  final amt = double.tryParse(amountStr) ?? 0;
                  final remaining = invoiceAmount - alreadyPaid;
                  if (amountStr.isEmpty || amt <= 0) {
                    setDialogState(() => errorMsg = '请输入有效金额');
                    return;
                  }
                  if (amt > remaining) {
                    setDialogState(() => errorMsg = '收款金额不能超过剩余应收款 \u{FFE5}${remaining.toStringAsFixed(2)}');
                    return;
                  }

                  // Method-specific validation
                  if (selectedMethod == 'bank_transfer' || selectedMethod == 'cheque') {
                    if (refNoCtrl.text.trim().isEmpty) {
                      final label = selectedMethod == 'bank_transfer' ? '银行流水号' : '支票号码';
                      setDialogState(() => errorMsg = '请输入$label（必填）');
                      return;
                    }
                    if (voucherBytes == null || voucherFileName == null) {
                      setDialogState(() => errorMsg = '必须上传凭证文件');
                      return;
                    }
                  } else if (selectedMethod == 'other') {
                    if (voucherBytes == null || voucherFileName == null) {
                      setDialogState(() => errorMsg = '必须上传凭证文件');
                      return;
                    }
                    if (voucherDescCtrl.text.trim().isEmpty) {
                      setDialogState(() => errorMsg = '请填写凭证说明（其他方式必须填写凭证说明）');
                      return;
                    }
                  }

                  try {
                    await _api.dio.post('/finance/payments', data: {
                      'invoice_id': invoiceId,
                      'amount': double.parse(amountStr),
                      'payment_date': paymentDate,
                      'payment_method': selectedMethod,
                      'ref_no': refNoCtrl.text,
                      'notes': notesCtrl.text,
                    });
                  } catch (e) {
                    setDialogState(() => errorMsg = '收款失败: $e');
                    return;
                  }

                  // Upload voucher (skip for cash)
                  if (selectedMethod != 'cash' && voucherBytes != null && voucherFileName != null) {
                    try {
                      final formData = FormData.fromMap({
                        'file': MultipartFile.fromBytes(
                          voucherBytes!,
                          filename: voucherFileName,
                        ),
                        'invoice_id': invoiceId,
                        'description': voucherDescCtrl.text,
                      });
                      await _api.dio.post(
                        '/finance/vouchers/upload',
                        data: formData,
                      );
                    } catch (e) {
                      voucherError = '收款成功，但凭证上传失败: $e';
                    }
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadAllPayments();
                  ref
                      .read(financeInvoiceProvider.notifier)
                      .load(status: _selectedStatus);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(voucherError ?? '收款记录添加成功')));
                  }
                },
                child: Text(selectedMethod == 'cash' ? '确认添加' : '确认添加并上传凭证')),
          ],
        ),
      ),
    );
  }

  // ─── Delete confirmation ───

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? errorMsg;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('确认删除'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('确定要删除此发票吗？此操作不可撤销。'),
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                    ]),
                  ),
                ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  try {
                    await _api.dio.delete('/finance/invoices/$id');
                    if (ctx.mounted) Navigator.pop(ctx);
                    _paymentsCache.remove(id);
                    _paymentTotals.remove(id);
                    _voucherCache.remove(id);
                    ref
                        .read(financeInvoiceProvider.notifier)
                        .load(status: _selectedStatus);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('删除成功')));
                    }
                  } catch (e) {
                    setDialogState(() => errorMsg = '删除失败: $e');
                  }
                },
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
    );
  }
}

class _TableCell extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final VoidCallback? onTap;
  const _TableCell(this.child, {required this.isDark, this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );
  }
}

class _InvoiceActionCell extends StatelessWidget {
  final String invoiceId;
  final String status;
  final double remaining;
  final bool isDark;
  final VoidCallback onPay;
  final VoidCallback onDetail;

  const _InvoiceActionCell({
    required this.invoiceId, required this.status, required this.remaining,
    required this.isDark, required this.onPay, required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (status != 'paid' && status != 'cancelled')
          _MiniBtn(Icons.payment, '收款', AppTheme.green, onPay),
        const SizedBox(width: 4),
        _MiniBtn(Icons.visibility, '详情', isDark ? Colors.white54 : Colors.black54, onDetail),
      ]),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniBtn(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(fontSize: 11, color: color)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
