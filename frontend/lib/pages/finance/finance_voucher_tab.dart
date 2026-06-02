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

class FinanceVoucherTab extends StatefulWidget {
  final String? settlementId;
  final String? expenseId;
  final String? invoiceId;

  const FinanceVoucherTab({super.key, this.settlementId, this.expenseId, this.invoiceId});

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
  int _page = 0;
  static const int _pageSize = 20;

  List<Map<String, dynamic>> get _pagedItems {
    final start = _page * _pageSize;
    final end = start + _pageSize;
    if (start >= _filteredItems.length) return [];
    return _filteredItems.sublist(start, end > _filteredItems.length ? _filteredItems.length : end);
  }

  int get _totalPages => (_filteredItems.length / _pageSize).ceil();

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
      if (widget.invoiceId != null) params['invoice_id'] = widget.invoiceId;
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
      _page = 0;
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
      if (widget.invoiceId != null) formDataMap['invoice_id'] = widget.invoiceId;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
      // Breadcrumb
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(children: [
          Text('首页', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: Colors.grey))),
          Text('财务', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: Colors.grey))),
          Text('凭证管理', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
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
      // Table
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filteredItems.isEmpty
                ? Center(child: Text('暂无凭证',
                    style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      final w = constraints.maxWidth;
                      if (w >= 800) return _buildVoucherTable(isDark);
                      return _buildVoucherCards(isDark, w);
                    },
                  ),
      ),
      if (_filteredItems.isNotEmpty && _totalPages > 1) _buildPagination(isDark),
    ]);
  }

  Widget _buildVoucherTable(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.6), 1: FlexColumnWidth(0.8),
          2: FlexColumnWidth(1.0), 3: FlexColumnWidth(1.2),
          4: FixedColumnWidth(100),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 0.5),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: isDark ? AppTheme.darkSurfaceAlt : const Color(0xFFF5F5FA)),
            children: const [
              _TableHeader('描述'), _TableHeader('类型'), _TableHeader('关联'),
              _TableHeader('日期'), _TableHeader('操作'),
            ],
          ),
          ..._pagedItems.map((v) => _buildVoucherTableRow(v, isDark)),
        ],
      ),
    );
  }

  TableRow _buildVoucherTableRow(Map<String, dynamic> v, bool isDark) {
    final id = v['id'] as String;
    final type = v['type'] as String? ?? 'invoice';
    final desc = v['description'] as String? ?? '';
    final fileId = v['file_id'] as String?;
    final date = (v['created_at'] as String? ?? '');
    final hasS = v['settlement_id'] != null;
    final hasE = v['expense_id'] != null;
    final hasI = v['invoice_id'] != null;
    final rel = (hasS && hasE && hasI) ? '结算+报销+发票'
        : (hasS && hasE) ? '结算+报销'
        : (hasS && hasI) ? '结算+发票'
        : (hasE && hasI) ? '报销+发票'
        : hasS ? '结算' : hasE ? '报销' : hasI ? '发票' : '-';

    return TableRow(children: [
      _TableCell(Text(desc, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis), isDark: isDark),
      _TableCell(Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: AppTheme.green, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(_typeNames[type] ?? type, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
      ]), isDark: isDark),
      _TableCell(Text(rel, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)), isDark: isDark),
      _TableCell(Text(date.length >= 10 ? date.substring(0, 10) : date, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)), isDark: isDark),
      _TableCell(Row(mainAxisSize: MainAxisSize.min, children: [
        if (fileId != null)
          Tooltip(
            message: '预览',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: fileId))),
              child: Container(width: 28, height: 28, alignment: Alignment.center, child: Icon(Icons.visibility_rounded, size: 16, color: AppTheme.blue)),
            ),
          ),
        Tooltip(
          message: '删除',
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => _delete(id),
            child: Container(width: 28, height: 28, alignment: Alignment.center, child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300)),
          ),
        ),
      ]), isDark: isDark),
    ]);
  }

  Widget _buildVoucherCards(bool isDark, double width) {
    final cols = width >= 500 ? 2 : 1;
    if (cols == 1) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _pagedItems.length,
        itemBuilder: (_, i) => _buildVoucherCard(_pagedItems[i], isDark),
      );
    }
    final cardWidth = (width - 12 * (cols + 1)) / cols;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: _pagedItems.map((v) => SizedBox(
          width: cardWidth,
          child: _buildVoucherCard(v, isDark),
        )).toList(),
      ),
    );
  }

  Widget _buildVoucherCard(Map<String, dynamic> v, bool isDark) {
    final type = v['type'] as String? ?? 'invoice';
    final desc = v['description'] as String? ?? '';
    final date = (v['created_at'] as String? ?? '');
    final fileId = v['file_id'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: fileId != null ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: fileId!))) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: (_typeColor(type)).withAlpha(isDark ? 20 : 15)),
                child: Icon(_typeIcons[type] ?? Icons.attach_file_rounded, color: _typeColor(type), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: _typeColor(type))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      _typeNames[type] ?? type,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                    )),
                  ]),
                  const SizedBox(height: 2),
                  Text(desc.isNotEmpty ? desc : '无描述', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                  const SizedBox(height: 2),
                  Text(date.length >= 10 ? date.substring(0, 10) : date, style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                ]),
              ),
              const SizedBox(width: 4),
              Column(mainAxisSize: MainAxisSize.min, children: [
                if (fileId != null)
                  _VoucherActionChip(Icons.visibility_rounded, '查看', AppTheme.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: fileId!)))),
                const SizedBox(height: 4),
                _VoucherActionChip(Icons.delete_outline, '删除', Colors.red.shade300, () => _delete(v['id'] as String)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'invoice': return AppTheme.blue;
      case 'receipt': return AppTheme.green;
      case 'contract': return AppTheme.orange;
      default: return Colors.grey;
    }
  }

  Widget _buildPagination(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: _page > 0 ? () => setState(() => _page--) : null),
        Text('${_page + 1} / $_totalPages', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
        IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: _page < _totalPages - 1 ? () => setState(() => _page++) : null),
      ]),
    );
  }
}

class _VoucherActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _VoucherActionChip(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 2),
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
            ]),
          ),
        ),
      ),
    );
  }
}
