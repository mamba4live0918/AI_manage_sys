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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showEditDialog(context, b),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                          Chip(label: Text(b.status, style: const TextStyle(fontSize: 11))),
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : Colors.black54),
                            onSelected: (v) {
                              if (v == 'edit') _showEditDialog(context, b);
                              if (v == 'delete') _confirmDelete(context, b.id, b.name);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 20), SizedBox(width: 8), Text('编辑')])),
                              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 20), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
                            ],
                          ),
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
                  ),
                );
              },
            ),
    );
  }

  void _showEditDialog(BuildContext context, BudgetData budget) {
    final nameCtrl = TextEditingController(text: budget.name);
    final amountCtrl = TextEditingController(text: budget.totalAmount.toStringAsFixed(0));
    final yearCtrl = TextEditingController(text: budget.year.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑预算'),
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
              await _api.dio.put('/finance/budgets/${budget.id}', data: {
                'name': nameCtrl.text,
                'total_amount': double.tryParse(amountCtrl.text) ?? budget.totalAmount,
                'year': int.tryParse(yearCtrl.text) ?? budget.year,
              });
              if (ctx.mounted) Navigator.pop(ctx);
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
      ),
    );
  }

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
