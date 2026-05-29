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
                  child: ListTile(
                    title: Text(inv.invoiceNo.isNotEmpty ? inv.invoiceNo : '无发票号'),
                    subtitle: Text('¥${inv.amount.toStringAsFixed(2)} | 税额: ¥${inv.taxAmount.toStringAsFixed(2)}'),
                    trailing: Chip(
                      label: Text(statusLabels[inv.status] ?? inv.status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      backgroundColor: statusColors[inv.status] ?? Colors.grey,
                    ),
                  ),
                );
              },
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
              await _api.dio.post('/api/finance/invoices', data: {
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
