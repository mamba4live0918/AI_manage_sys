import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _settlementStatusNames = {
  'pending': '待结算', 'in_progress': '结算中', 'completed': '已完成', 'cancelled': '已取消',
};

const _statusColors = {
  'pending': AppTheme.orange,
  'in_progress': AppTheme.blue,
  'completed': AppTheme.green,
  'cancelled': Colors.grey,
};

const _statusTransitions = {
  'pending': ['in_progress', 'cancelled'],
  'in_progress': ['completed', 'cancelled'],
  'completed': [],
  'cancelled': [],
};

class FinanceSettlementTab extends StatefulWidget {
  const FinanceSettlementTab({super.key});

  @override
  State<FinanceSettlementTab> createState() => _FinanceSettlementTabState();
}

class _FinanceSettlementTabState extends State<FinanceSettlementTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{'limit': 100};
      if (_statusFilter.isNotEmpty) params['status'] = _statusFilter;
      final resp = await _api.dio.get('/finance/settlements', queryParameters: params);
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    await _api.dio.put('/finance/settlements/$id', data: {'status': newStatus});
    _load();
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除结算'),
        content: const Text('确定要删除此结算记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/finance/settlements/$id');
      _load();
    }
  }

  Future<void> _create() async {
    final amountCtrl = TextEditingController();
    final invoiceCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    PlatformFile? pickedFile;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建结算'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: '金额 *'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: invoiceCtrl, decoration: const InputDecoration(labelText: '发票号')),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '备注')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: Icon(pickedFile != null ? Icons.check_circle : Icons.attach_file_rounded, size: 18,
                    color: pickedFile != null ? AppTheme.green : null),
                label: Text(pickedFile?.name ?? '上传凭证 (可选)'),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    withData: false, allowMultiple: false,
                    type: FileType.custom,
                    allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
                  );
                  if (result != null && result.files.isNotEmpty) {
                    final f = result.files.first;
                    if (f.path != null || f.bytes != null) {
                      setDlg(() => pickedFile = f);
                    }
                  }
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || amountCtrl.text.trim().isEmpty) return;

    final resp = await _api.dio.post('/finance/settlements', data: {
      'amount': double.tryParse(amountCtrl.text) ?? 0.0,
      'invoice_no': invoiceCtrl.text.trim(),
      'notes': notesCtrl.text.trim(),
    });
    final settlementId = resp.data['id'] as String;

    if (pickedFile != null) {
      final fileBytes = pickedFile!.path != null ? await File(pickedFile!.path!).readAsBytes() : pickedFile!.bytes;
      if (fileBytes == null) { _load(); return; }
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: pickedFile!.name),
        'type': 'invoice',
        'description': '结算凭证 - ${invoiceCtrl.text.trim()}',
        'settlement_id': settlementId,
      });
      await _api.dio.post('/finance/vouchers/upload', data: formData);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(height: 40, child: ElevatedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建结算'),
            )),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'pending', 'in_progress', 'completed', 'cancelled'].map((s) {
            final selected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s.isEmpty ? '全部' : _settlementStatusNames[s] ?? s),
                selected: selected,
                onSelected: (_) { _statusFilter = selected ? '' : s; _load(); },
              ),
            );
          }).toList()),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(child: Text('暂无结算记录', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final s = _items[i];
                      final id = s['id'] as String;
                      final amount = s['amount'] as num? ?? 0;
                      final status = s['status'] as String? ?? 'pending';
                      final invoice = s['invoice_no'] as String? ?? '';
                      final statusColor = _statusColors[status] ?? Colors.grey;
                      final transitions = _statusTransitions[status] ?? [];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withAlpha(30),
                            child: Icon(Icons.receipt_long_rounded, color: statusColor, size: 20),
                          ),
                          title: Text('\$${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text([invoice, s['notes'] ?? ''].where((x) => x.isNotEmpty).join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: statusColor.withAlpha(25)),
                              child: Text(_settlementStatusNames[status] ?? status, style: TextStyle(fontSize: 11, color: statusColor)),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18),
                              onSelected: (action) {
                                if (action == 'delete') {
                                  _delete(id);
                                } else {
                                  _updateStatus(id, action);
                                }
                              },
                              itemBuilder: (_) => [
                                ...transitions.map((t) => PopupMenuItem(
                                  value: t,
                                  child: Text('改为「${_settlementStatusNames[t] ?? t}」'),
                                )),
                                if (transitions.isNotEmpty)
                                  const PopupMenuDivider(),
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
