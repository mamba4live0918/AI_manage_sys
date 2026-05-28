import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../preview/preview_page.dart';

const _typeNames = {'invoice': '发票', 'receipt': '收据', 'contract': '合同', 'other': '其他'};
const _typeIcons = {
  'invoice': Icons.receipt_long_rounded,
  'receipt': Icons.description_rounded,
  'contract': Icons.assignment_rounded,
  'other': Icons.attach_file_rounded,
};

class FinanceVoucherTab extends StatefulWidget {
  final String? settlementId;
  final String? expenseId;

  const FinanceVoucherTab({super.key, this.settlementId, this.expenseId});

  @override
  State<FinanceVoucherTab> createState() => _FinanceVoucherTabState();
}

class _FinanceVoucherTabState extends State<FinanceVoucherTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _typeFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{'limit': 200};
      if (widget.settlementId != null) params['settlement_id'] = widget.settlementId;
      if (widget.expenseId != null) params['expense_id'] = widget.expenseId;
      final resp = await _api.dio.get('/finance/vouchers', queryParameters: params);
      setState(() {
        _allItems = List<Map<String, dynamic>>.from(resp.data['items']);
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filteredItems = _allItems.where((v) {
        if (_typeFilter.isNotEmpty && (v['type'] ?? '') != _typeFilter) return false;
        if (q.isEmpty) return true;
        final desc = (v['description'] ?? '').toLowerCase();
        final typeName = _typeNames[v['type']] ?? '';
        return desc.contains(q) || typeName.contains(q);
      }).toList();
    });
  }

  Future<void> _upload() async {
    String type = 'invoice';
    final descCtrl = TextEditingController();

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final fileBytes = picked.path != null ? await File(picked.path!).readAsBytes() : picked.bytes;
    if (fileBytes == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法读取文件')));
      return;
    }

    descCtrl.text = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('上传凭证'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.insert_drive_file_rounded, size: 20, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(child: Text(picked.name, overflow: TextOverflow.ellipsis)),
                Text('${(picked.size / 1024).toStringAsFixed(0)} KB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: '类型'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: type, isExpanded: true, isDense: true,
                    items: _typeNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDlg(() => type = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, maxLines: 2,
                  decoration: const InputDecoration(labelText: '描述')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('上传')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      final formDataMap = <String, dynamic>{
        'file': MultipartFile.fromBytes(fileBytes, filename: picked.name),
        'type': type,
        'description': descCtrl.text.trim(),
      };
      if (widget.settlementId != null) formDataMap['settlement_id'] = widget.settlementId;
      if (widget.expenseId != null) formDataMap['expense_id'] = widget.expenseId;
      final formData = FormData.fromMap(formDataMap);
      await _api.dio.post('/finance/vouchers/upload', data: formData);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('凭证上传成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除凭证'),
        content: const Text('确定要删除此凭证吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: AppTheme.red))),
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
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: '搜索凭证描述或类型...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { _searchCtrl.clear(); _applyFilter(); })
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (_) => _applyFilter(),
        ),
      ),
      // Upload button + type chips
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: _upload,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('上传凭证', style: TextStyle(fontSize: 13)),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: ['', 'invoice', 'receipt', 'contract', 'other'].map((t) {
                final selected = _typeFilter == t;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilterChip(
                    label: Text(t.isEmpty ? '全部' : _typeNames[t] ?? t, style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (_) { _typeFilter = selected ? '' : t; _applyFilter(); },
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              }).toList()),
            ),
          ),
        ]),
      ),
      // Results count
      if (_searchCtrl.text.isNotEmpty || _typeFilter.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('找到 ${_filteredItems.length} 条凭证',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
        ),
      // List
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filteredItems.isEmpty
                ? Center(child: Text('暂无凭证',
                    style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _filteredItems.length,
                    itemBuilder: (_, i) {
                      final v = _filteredItems[i];
                      final id = v['id'] as String;
                      final type = v['type'] as String? ?? 'invoice';
                      final desc = v['description'] as String? ?? '';
                      final fileId = v['file_id'] as String?;
                      final hasSettlement = v['settlement_id'] != null;
                      final hasExpense = v['expense_id'] != null;
                      final icon = _typeIcons[type] ?? Icons.attach_file_rounded;

                      String? subtitle;
                      if (hasSettlement && hasExpense) {
                        subtitle = '关联: 结算 + 报销';
                      } else if (hasSettlement) {
                        subtitle = '关联: 结算';
                      } else if (hasExpense) {
                        subtitle = '关联: 报销';
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: fileId != null ? const Color(0xFFE8F5E9) : const Color(0xFFECEFF1),
                            child: Icon(icon, color: AppTheme.green, size: 20),
                          ),
                          title: Text(_typeNames[type] ?? type, maxLines: 1),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(desc, maxLines: 2),
                              if (subtitle != null)
                                Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (fileId != null)
                              IconButton(
                                icon: const Icon(Icons.visibility_rounded, size: 18, color: AppTheme.blue),
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => PreviewPage(fileId: fileId),
                                  ));
                                },
                                tooltip: '预览凭证',
                              ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18),
                              onSelected: (action) {
                                if (action == 'delete') _delete(id);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'delete',
                                    child: Text('删除', style: TextStyle(color: AppTheme.red))),
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
