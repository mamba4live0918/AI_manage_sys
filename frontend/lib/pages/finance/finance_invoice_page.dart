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
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(financeInvoiceProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeInvoiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('发票管理'),
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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.items.length,
              itemBuilder: (_, i) {
                final inv = state.items[i];
                final statusColors = {'draft': Colors.grey, 'issued': Colors.orange, 'partial': Colors.blue, 'paid': Colors.green};
                final statusLabels = {'draft': '草稿', 'issued': '已开票', 'partial': '部分收款', 'paid': '已收款'};
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showDetailSheet(context, inv, statusLabels, statusColors),
                    child: ListTile(
                      title: Text(inv.invoiceNo.isNotEmpty ? inv.invoiceNo : '无发票号'),
                      subtitle: Text('¥${inv.amount.toStringAsFixed(2)} | 税额: ¥${inv.taxAmount.toStringAsFixed(2)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Chip(
                          label: Text(statusLabels[inv.status] ?? inv.status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: statusColors[inv.status] ?? Colors.grey,
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : Colors.black54),
                          onSelected: (v) {
                            if (v == 'delete') _confirmDelete(context, inv.id);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 20), SizedBox(width: 8), Text('删除')])),
                          ],
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showDetailSheet(BuildContext context, InvoiceData inv, Map<String, String> statusLabels, Map<String, Color> statusColors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    String selectedStatus = inv.status;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('发票详情', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(height: 20),
                _detailRow('发票号', inv.invoiceNo.isNotEmpty ? inv.invoiceNo : '无', labelColor, textColor),
                _detailRow('金额', '¥${inv.amount.toStringAsFixed(2)}', labelColor, textColor),
                _detailRow('税额', '¥${inv.taxAmount.toStringAsFixed(2)}', labelColor, textColor),
                _detailRow('税率', '${(inv.taxRate * 100).toStringAsFixed(0)}%', labelColor, textColor),
                _detailRow('开票日期', inv.issueDate ?? '未设置', labelColor, textColor),
                _detailRow('到期日期', inv.dueDate ?? '未设置', labelColor, textColor),
                _detailRow('备注', inv.notes.isNotEmpty ? inv.notes : '无', labelColor, textColor),
                if (inv.createdAt != null) _detailRow('创建时间', inv.createdAt!, labelColor, textColor),
                const SizedBox(height: 16),
                Row(children: [
                  Text('状态', style: TextStyle(color: labelColor, fontSize: 14)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: selectedStatus,
                      isExpanded: true,
                      items: ['draft', 'issued', 'partial', 'paid'].map((s) => DropdownMenuItem(
                        value: s,
                        child: Chip(
                          label: Text(statusLabels[s] ?? s, style: const TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: statusColors[s] ?? Colors.grey,
                        ),
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) setSheetState(() => selectedStatus = v);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selectedStatus == inv.status ? null : () async {
                      try {
                        await _api.dio.put('/finance/invoices/${inv.id}', data: {'status': selectedStatus});
                        if (ctx.mounted) Navigator.pop(ctx);
                        ref.read(financeInvoiceProvider.notifier).load();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('状态更新成功')));
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
                        }
                      }
                    },
                    child: const Text('更新状态'),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, Color labelColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(color: labelColor, fontSize: 14))),
        Expanded(child: Text(value, style: TextStyle(color: textColor, fontSize: 14))),
      ]),
    );
  }

  void _confirmDelete(BuildContext context, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此发票吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await _api.dio.delete('/finance/invoices/$id');
                Navigator.pop(ctx);
                ref.read(financeInvoiceProvider.notifier).load();
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

  void _showCreateDialog(BuildContext context) {
    final invoiceNoCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final taxAmountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建发票'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: invoiceNoCtrl, decoration: const InputDecoration(labelText: '发票号')),
            TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: '金额'), keyboardType: TextInputType.number),
            TextField(controller: taxAmountCtrl, decoration: const InputDecoration(labelText: '税额'), keyboardType: TextInputType.number),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: '备注')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            try {
              await _api.dio.post('/finance/invoices', data: {
                'invoice_no': invoiceNoCtrl.text,
                'amount': double.tryParse(amountCtrl.text) ?? 0,
                'tax_amount': double.tryParse(taxAmountCtrl.text) ?? 0,
                'notes': notesCtrl.text,
                'status': 'issued',
              });
              Navigator.pop(ctx);
              ref.read(financeInvoiceProvider.notifier).load();
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
            }
          }, child: const Text('创建')),
        ],
      ),
    );
  }
}
