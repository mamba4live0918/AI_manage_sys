import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _expenseCategoryNames = {
  'travel': '差旅', 'office': '办公', 'entertainment': '招待', 'other': '其他',
};
const _expenseStatusNames = {
  'pending': '待审批', 'approved': '已通过', 'rejected': '已驳回', 'paid': '已支付',
};
const _expenseTypeNames = {
  'reimbursement': '员工报销',
  'direct': '直接支出',
};

class FinanceExpenseTab extends StatefulWidget {
  const FinanceExpenseTab({super.key});

  @override
  State<FinanceExpenseTab> createState() => _FinanceExpenseTabState();
}

class _FinanceExpenseTabState extends State<FinanceExpenseTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _statusFilter = '';
  String _typeFilter = '';

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
      if (_typeFilter.isNotEmpty) params['expense_type'] = _typeFilter;
      final resp = await _api.dio.get('/finance/expenses', queryParameters: params);
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'other';
    String expenseType = 'reimbursement';
    PlatformFile? pickedFile;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建支出'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: '金额 *'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '类别'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: category, isExpanded: true, isDense: true,
                    items: _expenseCategoryNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDlg(() => category = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('支出类型', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                selected: {expenseType},
                onSelectionChanged: (v) => setDlg(() => expenseType = v.first),
                segments: const [
                  ButtonSegment(value: 'reimbursement', label: Text('员工报销'), icon: Icon(Icons.person, size: 16)),
                  ButtonSegment(value: 'direct', label: Text('直接支出'), icon: Icon(Icons.business, size: 16)),
                ],
              ),
              if (expenseType == 'reimbursement')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('员工报销需要审批', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('直接支出自动完成，无需审批', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '描述')),
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
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('提交')),
          ],
        ),
      ),
    );
    if (ok != true || amountCtrl.text.trim().isEmpty) return;

    final resp = await _api.dio.post('/finance/expenses', data: {
      'amount': double.tryParse(amountCtrl.text) ?? 0.0,
      'category': category,
      'expense_type': expenseType,
      'description': descCtrl.text.trim(),
    });
    final expenseId = resp.data['id'] as String;

    if (pickedFile != null) {
      final fileBytes = pickedFile!.path != null ? await File(pickedFile!.path!).readAsBytes() : pickedFile!.bytes;
      if (fileBytes == null) { _load(); return; }
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: pickedFile!.name),
        'type': category == 'travel' ? 'receipt' : 'invoice',
        'description': descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : pickedFile!.name,
        'expense_id': expenseId,
      });
      await _api.dio.post('/finance/vouchers/upload', data: formData);
    }
    _load();
  }

  Future<void> _approve(String id, String action) async {
    await _api.dio.put('/finance/expenses/$id', data: {'status': action});
    _load();
  }

  Future<void> _delete(String id) async {
    await _api.dio.delete('/finance/expenses/$id');
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
              label: const Text('新建支出'),
            )),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'pending', 'approved', 'rejected', 'paid'].map((s) {
            final selected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s.isEmpty ? '全部' : _expenseStatusNames[s] ?? s),
                selected: selected,
                onSelected: (_) { _statusFilter = selected ? '' : s; _load(); },
              ),
            );
          }).toList()),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'reimbursement', 'direct'].map((t) {
            final selected = _typeFilter == t;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(t.isEmpty ? '全部类型' : _expenseTypeNames[t] ?? t),
                selected: selected,
                onSelected: (_) { _typeFilter = selected ? '' : t; _load(); },
              ),
            );
          }).toList()),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(child: Text('暂无支出记录', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final e = _items[i];
                      final id = e['id'] as String;
                      final amount = e['amount'] as num? ?? 0;
                      final category = e['category'] as String? ?? 'other';
                      final status = e['status'] as String? ?? 'pending';
                      final expType = e['expense_type'] as String? ?? 'reimbursement';
                      final bool isReimbursement = expType == 'reimbursement';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isReimbursement ? const Color(0xFFE3F2FD) : const Color(0xFFE8F5E9),
                            child: Icon(Icons.money_rounded, color: isReimbursement ? AppTheme.blue : AppTheme.green, size: 20),
                          ),
                          title: Row(mainAxisSize: MainAxisSize.min, children: [
                            Flexible(child: Text('\$${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: isReimbursement ? AppTheme.blue.withAlpha(20) : AppTheme.green.withAlpha(20),
                              ),
                              child: Text(
                                isReimbursement ? '报销' : '支出',
                                style: TextStyle(fontSize: 10, color: isReimbursement ? AppTheme.blue : AppTheme.green, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ]),
                          subtitle: Text([_expenseCategoryNames[category] ?? category, e['description'] ?? ''].where((x) => x.isNotEmpty).join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: AppTheme.red.withAlpha(20)),
                              child: Text(_expenseStatusNames[status] ?? status, style: const TextStyle(fontSize: 11, color: AppTheme.red)),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18),
                              onSelected: (action) {
                                if (action == 'delete') {
                                  _delete(id);
                                } else {
                                  _approve(id, action);
                                }
                              },
                              itemBuilder: (_) {
                                final items = <PopupMenuEntry<String>>[];
                                if (isReimbursement && status == 'pending') {
                                  items.add(const PopupMenuItem(value: 'approved', child: Text('通过', style: TextStyle(color: AppTheme.green))));
                                  items.add(const PopupMenuItem(value: 'rejected', child: Text('驳回', style: TextStyle(color: AppTheme.red))));
                                }
                                items.add(const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))));
                                return items;
                              },
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
