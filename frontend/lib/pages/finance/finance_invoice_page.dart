import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/finance_providers.dart';
import '../../models/finance_models.dart';
import '../../services/api_client.dart';
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
  bool _loadingPayments = false;

  static const _statusOptions = ['', 'draft', 'issued', 'partial', 'paid'];
  static const _statusLabels = {
    '': '全部',
    'draft': '草稿',
    'issued': '已开票',
    'partial': '部分收款',
    'paid': '已收款',
  };
  static const _statusColors = {
    'draft': Colors.grey,
    'issued': Colors.orange,
    'partial': Colors.blue,
    'paid': Colors.green,
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
        title: const Text('发票管理'),
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
          _buildFilterBar(theme, isDark),
          const Divider(height: 1),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.items.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: state.items.length,
                        itemBuilder: (_, i) {
                          final inv = state.items[i];
                          return _buildInvoiceCard(inv, isDark, theme);
                        },
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
                    setState(() => _selectedStatus = s);
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

  // ─── Create dialog ───

  void _showCreateDialog(BuildContext context) {
    final invoiceNoCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final taxAmountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final projectIdCtrl = TextEditingController();
    final taxRateCtrl = TextEditingController(text: '0.13');
    String? issueDate;
    String? dueDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('创建发票'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
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
              TextField(
                  controller: projectIdCtrl,
                  decoration: const InputDecoration(labelText: '关联项目ID')),
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
              TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: '备注'),
                  maxLines: 2),
            ]),
          ),
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
                      'status': 'issued',
                    };
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
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('创建失败: $e')));
                    }
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
        final editInvoiceNoCtrl =
            TextEditingController(text: inv.invoiceNo);
        final editAmountCtrl =
            TextEditingController(text: inv.amount.toStringAsFixed(2));
        final editTaxAmountCtrl =
            TextEditingController(text: inv.taxAmount.toStringAsFixed(2));
        final editNotesCtrl = TextEditingController(text: inv.notes);

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
                        TextButton.icon(
                          icon: Icon(
                              isEditing ? Icons.visibility : Icons.edit,
                              size: 18),
                          label: Text(isEditing ? '查看' : '编辑'),
                          onPressed: () =>
                              setSheetState(() => isEditing = !isEditing),
                        ),
                      ]),
                      const SizedBox(height: 16),

                      if (isEditing) ...[
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
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(content: Text('更新失败: $e')));
                                }
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
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加收款'),
                          onPressed: () => _showPaymentDialog(
                              ctx,
                              inv.id,
                              inv.amount,
                              _paymentTotals[inv.id] ?? 0),
                        ),
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
                        ...payments.map((p) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
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
                            )),
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

  // ─── Payment dialog (reusable from card + detail sheet) ───

  void _showPaymentDialog(BuildContext context, String invoiceId,
      double invoiceAmount, double alreadyPaid) {
    final remaining = (invoiceAmount - alreadyPaid).clamp(0.0, double.infinity);
    final amountCtrl = TextEditingController();
    final refNoCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final voucherDescCtrl = TextEditingController();
    String selectedMethod = 'bank_transfer';
    String paymentDate = DateTime.now().toIso8601String().substring(0, 10);
    String? voucherFileName;
    Uint8List? voucherBytes;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加收款'),
          content: SizedBox(
            width: 420,
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
                            setDialogState(() => selectedMethod = v);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: refNoCtrl,
                      decoration:
                          const InputDecoration(labelText: '凭证号/流水号')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: '备注'),
                      maxLines: 2),

                  const SizedBox(height: 8),
                  // ─── Voucher upload section (mandatory) ───
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.upload_file, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '上传凭证',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(ctx).colorScheme.onSurface,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    '必须上传凭证文件',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // File picker + name display
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
                          color:
                              voucherFileName != null
                                  ? Theme.of(ctx).colorScheme.onSurface
                                  : Theme.of(ctx)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: voucherDescCtrl,
                    decoration: const InputDecoration(
                      labelText: '凭证说明',
                      hintText: '例如：发票、收据、合同复印件等',
                    ),
                    maxLines: 2,
                  ),
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
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请输入有效金额')));
                    }
                    return;
                  }
                  if (amt > remaining) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('收款金额不能超过剩余应收款 ¥${remaining.toStringAsFixed(2)}')));
                    }
                    return;
                  }
                  if (voucherBytes == null || voucherFileName == null) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('必须上传凭证文件')));
                    }
                    return;
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
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('收款失败: $e')));
                    }
                    return;
                  }

                  // Upload voucher
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
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('收款成功，但凭证上传失败: $e')));
                    }
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadAllPayments();
                  ref
                      .read(financeInvoiceProvider.notifier)
                      .load(status: _selectedStatus);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('收款记录添加成功')));
                  }
                },
                child: const Text('确认添加并上传凭证')),
          ],
        ),
      ),
    );
  }

  // ─── Delete confirmation ───

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此发票吗？此操作不可撤销。'),
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
                ref
                    .read(financeInvoiceProvider.notifier)
                    .load(status: _selectedStatus);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('删除成功')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('删除失败: $e')));
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
