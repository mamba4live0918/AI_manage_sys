import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/finance_providers.dart';
import '../../services/api_client.dart';

class FinanceBudgetPage extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const FinanceBudgetPage({super.key, this.onBack});

  @override
  ConsumerState<FinanceBudgetPage> createState() => _FinanceBudgetPageState();
}

class _FinanceBudgetPageState extends ConsumerState<FinanceBudgetPage> {
  final ApiClient _api = ApiClient();
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(financeBudgetProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeBudgetProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.items.length,
              itemBuilder: (_, i) {
                final b = state.items[i];
                final pct = b.totalAmount > 0 ? (b.usedAmount / b.totalAmount) : 0.0;
                final warnColor = pct > 0.9 ? Colors.red : pct > 0.7 ? Colors.orange : Colors.green;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                        Chip(label: Text(b.status, style: const TextStyle(fontSize: 11))),
                      ]),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation(warnColor),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text('已用: ¥${b.usedAmount.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                        const Spacer(),
                        Text('总额: ¥${b.totalAmount.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                        const Spacer(),
                        Text('${(pct * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: warnColor)),
                      ]),
                    ]),
                  ),
                );
              },
            ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: '2026');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建预算'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '预算名称')),
            TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: '金额'), keyboardType: TextInputType.number),
            TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: '年度'), keyboardType: TextInputType.number),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            try {
              await _api.dio.post('/finance/budgets', data: {
                'name': nameCtrl.text,
                'total_amount': double.tryParse(amountCtrl.text) ?? 0,
                'year': int.tryParse(yearCtrl.text) ?? 2026,
              });
              Navigator.pop(ctx);
              ref.read(financeBudgetProvider.notifier).load();
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
            }
          }, child: const Text('创建')),
        ],
      ),
    );
  }
}
