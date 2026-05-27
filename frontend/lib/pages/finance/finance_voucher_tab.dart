import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class FinanceVoucherTab extends StatefulWidget {
  const FinanceVoucherTab({super.key});

  @override
  State<FinanceVoucherTab> createState() => _FinanceVoucherTabState();
}

class _FinanceVoucherTabState extends State<FinanceVoucherTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/finance/vouchers', queryParameters: {'limit': 50});
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final descCtrl = TextEditingController();
    String type = 'invoice';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建凭证'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InputDecorator(
                decoration: const InputDecoration(labelText: '类型'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: type, isExpanded: true, isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'invoice', child: Text('发票')),
                      DropdownMenuItem(value: 'receipt', child: Text('收据')),
                      DropdownMenuItem(value: 'contract', child: Text('合同')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) => setDlg(() => type = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '描述')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _api.dio.post('/finance/vouchers', data: {
      'type': type,
      'description': descCtrl.text.trim(),
    });
    _load();
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除凭证'),
        content: const Text('确定要删除此凭证吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/finance/vouchers/$id');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(height: 40, child: ElevatedButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('新建凭证'),
        )),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(child: Text('暂无凭证', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final v = _items[i];
                      final id = v['id'] as String;
                      final type = v['type'] as String? ?? 'invoice';
                      final desc = v['description'] as String? ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE8F5E9),
                            child: Icon(Icons.attach_file_rounded, color: AppTheme.green, size: 20),
                          ),
                          title: Text(type, maxLines: 1),
                          subtitle: Text(desc, maxLines: 2),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (v['file_id'] != null)
                              Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.green.withAlpha(180)),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18),
                              onSelected: (action) {
                                if (action == 'delete') _delete(id);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                              ],
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
