import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../widgets/budget_tree_selector.dart';

const _expenseCategoryNames = {
  'travel': '差旅', 'office': '办公', 'entertainment': '招待',
  'equipment': '设备', 'salary': '工资', 'training': '培训',
  'marketing': '市场', 'other': '其他',
};
const _expenseStatusNames = {
  'pending': '待审批', 'approved': '已通过', 'rejected': '已驳回', 'paid': '已支付',
};
const _expenseTypeNames = {
  'reimbursement': '员工报销',
  'direct': '直接支出',
};

Color _categoryColor(String cat) {
  switch (cat) {
    case 'travel': return Colors.orange;
    case 'office': return Colors.blue;
    case 'entertainment': return Colors.purple;
    case 'equipment': return Colors.teal;
    case 'salary': return Colors.green;
    case 'training': return Colors.indigo;
    case 'marketing': return Colors.pink;
    case 'other': return Colors.grey;
    default: return Colors.grey;
  }
}

String _categoryLabel(String cat) => _expenseCategoryNames[cat] ?? cat;

Color _statusColor(String status) {
  switch (status) {
    case 'pending': return Colors.orange;
    case 'approved': return Colors.green;
    case 'rejected': return Colors.red;
    case 'paid': return Colors.green;
    default: return Colors.grey;
  }
}

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
  _TableCell(this.child, {required this.isDark, this.onTap});

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

class _ActionsCell extends StatelessWidget {
  final String id;
  final String status;
  final String expType;
  final bool isDark;
  final ValueChanged<String> onApprove;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ActionsCell({
    required this.id, required this.status, required this.expType,
    required this.isDark, required this.onApprove, required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isReimbursement = expType == 'reimbursement';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isReimbursement && status == 'pending') ...[
          _MiniBtn(Icons.check, '通过', AppTheme.green, () => onApprove('approved')),
          const SizedBox(width: 4),
          _MiniBtn(Icons.close, '驳回', Colors.red, () => onApprove('rejected')),
        ] else if (isReimbursement && status == 'approved') ...[
          _MiniBtn(Icons.payment, '支付', AppTheme.green, () => onApprove('paid')),
        ] else if (expType == 'direct') ...[
          _MiniBtn(Icons.edit_outlined, '编辑', isDark ? Colors.white54 : Colors.black54, onEdit),
          const SizedBox(width: 4),
          _MiniBtn(Icons.delete_outline, '删除', Colors.red, onDelete),
        ],
      ]),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniBtn(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(fontSize: 11, color: color)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class FinanceExpenseTab extends ConsumerStatefulWidget {
  const FinanceExpenseTab({super.key});

  @override
  ConsumerState<FinanceExpenseTab> createState() => _FinanceExpenseTabState();
}

class _FinanceExpenseTabState extends ConsumerState<FinanceExpenseTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _allItems = [];
  bool _loading = true;
  String _statusFilter = '';
  String _typeFilter = '';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, List<Map<String, dynamic>>> _voucherCache = {};
  bool _loadingVouchers = false;
  int _page = 0;
  static const int _pageSize = 20;

  List<Map<String, dynamic>> get _pagedItems {
    final start = _page * _pageSize;
    final end = start + _pageSize;
    if (start >= _items.length) return [];
    return _items.sublist(start, end > _items.length ? _items.length : end);
  }

  int get _totalPages => (_items.length / _pageSize).ceil();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{'limit': 100};
      if (_statusFilter.isNotEmpty) params['status'] = _statusFilter;
      if (_typeFilter.isNotEmpty) params['expense_type'] = _typeFilter;
      final resp = await _api.dio.get('/finance/expenses', queryParameters: params);
      setState(() {
        _allItems = List<Map<String, dynamic>>.from(resp.data['items']);
        _applySearch();
        _loading = false;
      });
      _loadVouchers();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      _items = _allItems;
    } else {
      final q = _searchQuery.toLowerCase();
      _items = _allItems.where((e) {
        final desc = (e['description'] as String? ?? '').toLowerCase();
        final cat = (e['category'] as String? ?? '').toLowerCase();
        final catLabel = (_expenseCategoryNames[e['category']] ?? '').toLowerCase();
        return desc.contains(q) || cat.contains(q) || catLabel.contains(q);
      }).toList();
    }
    _page = 0;
  }

  Future<void> _loadVouchers() async {
    if (_loadingVouchers) return;
    _loadingVouchers = true;
    try {
      final resp = await _api.dio.get('/finance/vouchers', queryParameters: {'limit': '1000'});
      final vouchers = List<Map<String, dynamic>>.from(resp.data['items']);
      _voucherCache.clear();
      for (final v in vouchers) {
        final expId = v['expense_id'] as String?;
        if (expId != null) {
          _voucherCache.putIfAbsent(expId, () => []).add(v);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingVouchers = false);
  }

  // ─── Create dialog ───

  Future<void> _create() async {
    final authState = ref.read(authProvider);
    final currentUser = authState.user;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'other';
    String expenseType = 'reimbursement';
    PlatformFile? pickedFile;
    String? errorMsg;
    String? selectedDeptId;
    List<Map<String, dynamic>>? deptList;
    bool deptListLoading = false;
    String? selectedBudgetId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建支出'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 550),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                      ]),
                    ),
                  ),
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
                const SizedBox(height: 4),
                // ── Department section ──
                currentUser != null && currentUser.departmentId != null
                    ? Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.business, size: 14, color: Colors.blue),
                          const SizedBox(width: 6),
                          Text('部门: ${currentUser.department}',
                              style: const TextStyle(fontSize: 12, color: Colors.blue)),
                        ]),
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text('请先选择部门', style: TextStyle(fontSize: 12, color: Colors.orange)),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 4),
                        deptList == null && !deptListLoading
                            ? SizedBox(
                                height: 32,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text('加载部门列表', style: TextStyle(fontSize: 12)),
                                  onPressed: () async {
                                    setDlg(() => deptListLoading = true);
                                    try {
                                      final resp = await _api.dio.get('/departments');
                                      setDlg(() {
                                        deptList = List<Map<String, dynamic>>.from(resp.data['items']);
                                        deptListLoading = false;
                                      });
                                    } catch (_) {
                                      setDlg(() => deptListLoading = false);
                                    }
                                  },
                                ),
                              )
                            : deptListLoading
                                ? const SizedBox(height: 20, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))))
                                : DropdownButtonFormField<String>(
                                    value: selectedDeptId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: '选择部门',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    ),
                                    items: (deptList ?? []).map((d) => DropdownMenuItem(
                                      value: d['id'] as String?,
                                      child: Text(d['name'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                                    )).toList(),
                                    onChanged: (v) => setDlg(() => selectedDeptId = v),
                                  ),
                      ]),
                const SizedBox(height: 8),
                BudgetTreeSelector(
                  label: '关联预算 (可选)',
                  onChanged: (v) => setDlg(() => selectedBudgetId = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '描述')),
                const SizedBox(height: 12),
                // Voucher upload section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.upload_file, size: 18),
                      const SizedBox(width: 8),
                      Text('上传凭证 (可选)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton.icon(
                        icon: Icon(pickedFile != null ? Icons.check_circle : Icons.attach_file_rounded, size: 16,
                            color: pickedFile != null ? AppTheme.green : null),
                        label: Text(pickedFile != null ? '已选择文件' : '选择文件'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: pickedFile != null ? AppTheme.green : Colors.grey.shade400),
                        ),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            withData: true, allowMultiple: false,
                            type: FileType.custom,
                            allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
                          );
                          if (result != null && result.files.isNotEmpty) {
                            setDlg(() => pickedFile = result.files.first);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          pickedFile?.name ?? '未选择文件',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: pickedFile != null ? Colors.black87 : Colors.grey),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('提交')),
          ],
        ),
      ),
    );
    if (ok != true || amountCtrl.text.trim().isEmpty) return;

    try {
      final expenseData = <String, dynamic>{
        'amount': double.tryParse(amountCtrl.text) ?? 0.0,
        'category': category,
        'expense_type': expenseType,
        'description': descCtrl.text.trim(),
      };
      if (selectedBudgetId != null) expenseData['budget_id'] = selectedBudgetId;
      if (selectedDeptId != null) expenseData['department_id'] = selectedDeptId;
      final resp = await _api.dio.post('/finance/expenses', data: expenseData);
      final expenseId = resp.data['id'] as String;

      final file = pickedFile;
      if (file != null && file.bytes != null) {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
          'type': category == 'travel' ? 'receipt' : 'invoice',
          'description': descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : file.name,
          'expense_id': expenseId,
        });
        await _api.dio.post('/finance/vouchers/upload', data: formData);
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('支出创建成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
      }
    }
  }

  // ─── Edit dialog ───

  Future<void> _edit(Map<String, dynamic> expense) async {
    final id = expense['id'] as String;
    final amountCtrl = TextEditingController(text: (expense['amount'] as num?)?.toStringAsFixed(2) ?? '');
    final descCtrl = TextEditingController(text: expense['description'] as String? ?? '');
    String category = expense['category'] as String? ?? 'other';
    String expenseType = expense['expense_type'] as String? ?? 'reimbursement';
    String? selectedBudgetId = expense['budget_id'] as String?;
    PlatformFile? pickedFile;
    String? errorMsg;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('编辑支出'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 550),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                      ]),
                    ),
                  ),
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
                BudgetTreeSelector(
                  label: '关联预算 (可选)',
                  initialBudgetId: selectedBudgetId,
                  onChanged: (v) => setDlg(() => selectedBudgetId = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '描述')),
                const SizedBox(height: 12),
                // Voucher upload section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.upload_file, size: 18),
                      const SizedBox(width: 8),
                      Text('上传凭证 (可选)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton.icon(
                        icon: Icon(pickedFile != null ? Icons.check_circle : Icons.attach_file_rounded, size: 16,
                            color: pickedFile != null ? AppTheme.green : null),
                        label: Text(pickedFile != null ? '已选择文件' : '选择文件'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: pickedFile != null ? AppTheme.green : Colors.grey.shade400),
                        ),
                        onPressed: () async {
                          final result = await FilePicker.platform.pickFiles(
                            withData: true, allowMultiple: false,
                            type: FileType.custom,
                            allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
                          );
                          if (result != null && result.files.isNotEmpty) {
                            setDlg(() => pickedFile = result.files.first);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          pickedFile?.name ?? '未选择文件',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: pickedFile != null ? Colors.black87 : Colors.grey),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      await _api.dio.put('/finance/expenses/$id', data: {
        'amount': double.tryParse(amountCtrl.text) ?? (expense['amount'] as num?)?.toDouble() ?? 0.0,
        'category': category,
        'expense_type': expenseType,
        'description': descCtrl.text.trim(),
        if (selectedBudgetId != null) 'budget_id': selectedBudgetId,
      });

      final file = pickedFile;
      if (file != null && file.bytes != null) {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
          'type': category == 'travel' ? 'receipt' : 'invoice',
          'description': descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : file.name,
          'expense_id': id,
        });
        await _api.dio.post('/finance/vouchers/upload', data: formData);
      }
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('支出更新成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失败: $e')));
      }
    }
  }

  Future<void> _approve(String id, String action) async {
    await _api.dio.put('/finance/expenses/$id', data: {'status': action});
    _load();
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除此支出记录吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.dio.delete('/finance/expenses/$id');
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  // ─── Detail bottom sheet ───

  void _showDetailSheet(Map<String, dynamic> e) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final labelColor = isDark ? Colors.white70 : Colors.black54;
    final id = e['id'] as String;
    final amount = e['amount'] as num? ?? 0;
    final category = e['category'] as String? ?? 'other';
    final status = e['status'] as String? ?? 'pending';
    final expType = e['expense_type'] as String? ?? 'reimbursement';
    final description = e['description'] as String? ?? '';
    final createdAt = e['created_at'] as String? ?? '';
    final bool isReimbursement = expType == 'reimbursement';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final vouchers = _voucherCache[id] ?? [];

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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: Text('支出详情',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
                  ),
                  if (status == 'pending')
                    TextButton.icon(
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('编辑'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _edit(e);
                      },
                    ),
                ]),
                const SizedBox(height: 20),
                // Amount prominent
                Center(
                  child: Text(
                    '\u{FFE5}${amount.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: textColor),
                  ),
                ),
                const SizedBox(height: 16),
                // Chips row
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(
                    label: Text(_expenseCategoryNames[category] ?? category, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: _categoryColor(category),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text(isReimbursement ? '员工报销' : '直接支出', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: isReimbursement ? AppTheme.blue : AppTheme.green,
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text(_expenseStatusNames[status] ?? status, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: _statusColor(status),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ]),
                const SizedBox(height: 20),
                _detailRow('金额', '\u{FFE5}${amount.toStringAsFixed(2)}', labelColor, textColor),
                _detailRow('类别', _expenseCategoryNames[category] ?? category, labelColor, textColor),
                _detailRow('类型', isReimbursement ? '员工报销' : '直接支出', labelColor, textColor),
                _detailRow('状态', _expenseStatusNames[status] ?? status, labelColor, textColor),
                if (description.isNotEmpty)
                  _detailRow('描述', description, labelColor, textColor),
                if (createdAt.isNotEmpty)
                  _detailRow('创建时间', _formatDate(createdAt), labelColor, textColor),

                // Reimbursement approval status
                if (isReimbursement) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('审批状态', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 12),
                  _approvalStep('提交', true, textColor, labelColor),
                  _approvalStep('审批', status == 'approved' || status == 'paid' || status == 'rejected', textColor, labelColor,
                      rejected: status == 'rejected'),
                  _approvalStep('支付', status == 'paid', textColor, labelColor),
                ],

                // Vouchers section
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(children: [
                  Text('凭证', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor)),
                  if (vouchers.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${vouchers.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ]),
                if (vouchers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text('暂无凭证', style: TextStyle(color: labelColor, fontSize: 14)),
                    ),
                  )
                else
                  ...vouchers.map((v) => _buildVoucherItem(v, isDark, textColor, labelColor, ctx)),

                // Delete button
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                    label: const Text('删除支出', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _delete(id);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, Color labelColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 70, child: Text(label, style: TextStyle(color: labelColor, fontSize: 14))),
        Expanded(child: Text(value, style: TextStyle(color: textColor, fontSize: 14))),
      ]),
    );
  }

  Widget _approvalStep(String label, bool done, Color textColor, Color labelColor, {bool rejected = false}) {
    final Color iconColor;
    final IconData icon;
    if (rejected) {
      icon = Icons.cancel;
      iconColor = Colors.red;
    } else if (done) {
      icon = Icons.check_circle;
      iconColor = Colors.green;
    } else {
      icon = Icons.radio_button_unchecked;
      iconColor = labelColor;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(
          fontSize: 14,
          color: done || rejected ? textColor : labelColor,
          fontWeight: done || rejected ? FontWeight.w500 : FontWeight.normal,
        )),
      ]),
    );
  }

  Widget _buildVoucherItem(Map<String, dynamic> v, bool isDark,
      Color textColor, Color labelColor, BuildContext ctx) {
    final typeLabels = {
      'invoice': '发票', 'receipt': '收据', 'contract': '合同', 'other': '其他',
    };
    final voucherType = typeLabels[v['type']] ?? (v['type'] as String?) ?? '未知';
    final description = (v['description'] as String?) ?? '';
    final createdAt = (v['created_at'] as String?) ?? '';
    final fileId = v['file_id'] as String?;

    return Material(
      color: isDark ? Colors.white10 : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (fileId != null) {
            _downloadVoucher(v);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: fileId != null
                      ? Colors.blue.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  fileId != null ? Icons.attach_file : Icons.description,
                  size: 20,
                  color: fileId != null ? Colors.blue : Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(voucherType, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textColor)),
                      if (fileId != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.visibility, size: 13, color: isDark ? Colors.white38 : Colors.black38),
                      ],
                    ]),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: labelColor)),
                    ],
                    if (createdAt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(_formatDate(createdAt), style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: () => _confirmDeleteVoucher(v, ctx),
                tooltip: '删除',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteVoucher(Map<String, dynamic> v, BuildContext bottomSheetCtx) {
    showDialog(
      context: context,
      builder: (ctx) {
        String? errorMsg;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('确认删除'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('确定要删除此凭证吗？'),
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                    ]),
                  ),
                ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  try {
                    await _api.dio.delete('/finance/vouchers/${v['id']}');
                    Navigator.pop(ctx); // close confirm dialog
                    Navigator.pop(bottomSheetCtx); // close detail sheet
                    _loadVouchers();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('凭证已删除')));
                    }
                  } catch (e) {
                    setDialogState(() => errorMsg = '删除失败: $e');
                  }
                },
                child: const Text('删除'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _downloadVoucher(Map<String, dynamic> voucher) async {
    final fileId = voucher['file_id'] as String?;
    if (fileId == null) return;

    showDialog(context: context, barrierDismissible: false, useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()));

    String? fileUrl, fileName;
    try {
      final resp = await _api.dio.get('/preview/file/$fileId');
      fileUrl = resp.data['url'] as String?;
      fileName = resp.data['name'] as String?;
    } catch (_) {}

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    if (fileUrl == null || !context.mounted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('获取文件失败')));
      }
      return;
    }

    final desc = (voucher['description'] as String?) ?? '';

    showDialog(context: context, useRootNavigator: true, builder: (ctx) => AlertDialog(
      title: Text(desc.isNotEmpty ? desc : '下载凭证'),
      content: Text(fileName ?? '文件'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('下载'),
          onPressed: () async {
            Navigator.pop(ctx);
            try {
              final dir = Directory.systemTemp;
              final savePath = '${dir.path}${Platform.pathSeparator}${fileName ?? 'file'}';
              await Dio().download(fileUrl!, savePath);
              await Process.run('cmd', ['/c', 'start', '', savePath]);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('下载失败')));
              }
            }
          },
        ),
      ],
    ));
  }

  String _formatDate(String iso) {
    try {
      return iso.substring(0, 10);
    } catch (_) {
      return iso;
    }
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Column(children: [
      // ── Search bar ──
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: '搜索描述、类别',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _applySearch();
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onChanged: (v) {
            setState(() {
              _searchQuery = v;
              _applySearch();
            });
          },
          onSubmitted: (_) {
            _applySearch();
          },
        ),
      ),

      // ── Create button ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建支出'),
          ),
        ),
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
          Text('支出管理', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
        ]),
      ),

      // ── Status filter chips ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'pending', 'approved', 'rejected', 'paid'].map((s) {
            final selected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  s.isEmpty ? '全部' : _expenseStatusNames[s] ?? s,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                selected: selected,
                selectedColor: theme.colorScheme.primary,
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                side: BorderSide.none,
                onSelected: (_) {
                  _statusFilter = selected ? '' : s;
                  _load();
                },
              ),
            );
          }).toList()),
        ),
      ),

      // ── Type filter chips ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'reimbursement', 'direct'].map((t) {
            final selected = _typeFilter == t;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  t.isEmpty ? '全部类型' : _expenseTypeNames[t] ?? t,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  ),
                ),
                selected: selected,
                selectedColor: theme.colorScheme.primary,
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                side: BorderSide.none,
                onSelected: (_) {
                  _typeFilter = selected ? '' : t;
                  _load();
                },
              ),
            );
          }).toList()),
        ),
      ),

      const SizedBox(height: 8),

      // ── Content: DataTable ──
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_items.isEmpty)
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('暂无支出记录', style: TextStyle(color: Colors.grey.shade500)),
          ]),
        )
      else
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.1),  // 金额
                1: FlexColumnWidth(0.7),  // 类别
                2: FlexColumnWidth(0.7),  // 类型
                3: FlexColumnWidth(1.2),  // 描述
                4: FlexColumnWidth(0.8),  // 日期
                5: FlexColumnWidth(0.8),  // 状态
                6: FlexColumnWidth(1.2),  // 操作
              },
              border: TableBorder(
                horizontalInside: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 0.5),
              ),
              children: [
                // Header row
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkSurfaceAlt : const Color(0xFFF5F5FA),
                  ),
                  children: const [
                    _TableHeader('金额'),
                    _TableHeader('类别'),
                    _TableHeader('类型'),
                    _TableHeader('描述'),
                    _TableHeader('日期'),
                    _TableHeader('状态'),
                    _TableHeader('操作'),
                  ],
                ),
                // Data rows
                ..._pagedItems.map((e) {
                  final status = e['status'] as String? ?? 'pending';
                  final cat = e['category'] as String? ?? 'other';
                  final type = e['expense_type'] as String? ?? 'reimbursement';
                  final desc = e['description'] as String? ?? '';
                  final date = (e['created_at'] as String? ?? '');
                  return TableRow(
                    children: [
                      _TableCell(
                        Text('\u{FFE5}${(e['amount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                        isDark: isDark, onTap: () => _showDetailSheet(e),
                      ),
                      _TableCell(
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: _categoryColor(cat), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(_categoryLabel(cat), style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                        ]),
                        isDark: isDark, onTap: () => _showDetailSheet(e),
                      ),
                      _TableCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (type == 'direct' ? AppTheme.green : AppTheme.accent).withAlpha(isDark ? 25 : 15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(type == 'direct' ? '直接' : '报销', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: type == 'direct' ? AppTheme.green : AppTheme.accent)),
                        ),
                        isDark: isDark, onTap: () => _showDetailSheet(e),
                      ),
                      _TableCell(
                        Text(desc, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        isDark: isDark, onTap: () => _showDetailSheet(e),
                      ),
                      _TableCell(
                        Text(date.length >= 10 ? date.substring(0, 10) : date, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                        isDark: isDark, onTap: () => _showDetailSheet(e),
                      ),
                      _TableCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withAlpha(isDark ? 30 : 20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_expenseStatusNames[status] ?? status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: _statusColor(status))),
                        ),
                        isDark: isDark, onTap: () => _showDetailSheet(e),
                      ),
                      _ActionsCell(
                        id: e['id'] as String,
                        status: status,
                        expType: type,
                        isDark: isDark,
                        onApprove: (action) => _approve(e['id'] as String, action),
                        onEdit: () => _edit(e),
                        onDelete: () => _delete(e['id'] as String),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      if (_totalPages > 1)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
            ),
            Text('${_page + 1} / $_totalPages', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              onPressed: _page < _totalPages - 1 ? () => setState(() => _page++) : null,
            ),
          ]),
        ),
    ]);
  }

  // ─── Empty state ───

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无支出记录',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('点击 + 创建'),
            onPressed: _create,
          ),
        ],
      ),
    );
  }

  // ─── Expense card ───

  Widget _buildExpenseCard(Map<String, dynamic> e, bool isDark, ThemeData theme) {
    final id = e['id'] as String;
    final amount = e['amount'] as num? ?? 0;
    final category = e['category'] as String? ?? 'other';
    final status = e['status'] as String? ?? 'pending';
    final expType = e['expense_type'] as String? ?? 'reimbursement';
    final description = e['description'] as String? ?? '';
    final createdAt = e['created_at'] as String? ?? '';
    final bool isReimbursement = expType == 'reimbursement';

    final catColor = _categoryColor(category);
    final statColor = _statusColor(status);

    // Progress for reimbursement approval
    double progress = 0;
    if (isReimbursement) {
      switch (status) {
        case 'pending': progress = 0.33; break;
        case 'approved': progress = 0.66; break;
        case 'paid': progress = 1.0; break;
        case 'rejected': progress = 0.66; break;
      }
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white54 : Colors.black45;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetailSheet(e),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: amount + status chip
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      '\u{FFE5}${amount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                  // Type tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isReimbursement
                          ? AppTheme.blue.withValues(alpha: isDark ? 0.3 : 0.15)
                          : AppTheme.green.withValues(alpha: isDark ? 0.3 : 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isReimbursement ? '报销' : '支出',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isReimbursement ? AppTheme.blue : AppTheme.green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statColor.withValues(alpha: isDark ? 0.35 : 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _expenseStatusNames[status] ?? status,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Category chip
              Wrap(spacing: 6, runSpacing: 4, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: isDark ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: catColor.withValues(alpha: 0.3), width: 0.5),
                  ),
                  child: Text(
                    _expenseCategoryNames[category] ?? category,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: catColor),
                  ),
                ),
              ]),

              const SizedBox(height: 8),

              // Subtitle: category label + description preview + date
              if (description.isNotEmpty || createdAt.isNotEmpty)
                Text(
                  [
                    if (description.isNotEmpty) description.length > 40 ? '${description.substring(0, 40)}...' : description,
                    if (createdAt.isNotEmpty) _formatDate(createdAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),

              // Progress indicator for reimbursements
              if (isReimbursement) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      status == 'rejected' ? Colors.red : statColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '审批进度 · ${_expenseStatusNames[status] ?? status}',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                ),
              ],

              // Action buttons row
              if (isReimbursement && status == 'pending') ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _approve(id, 'rejected'),
                      icon: const Icon(Icons.close, size: 16, color: Colors.red),
                      label: const Text('驳回', style: TextStyle(color: Colors.red, fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _approve(id, 'approved'),
                      icon: const Icon(Icons.check, size: 16, color: AppTheme.green),
                      label: const Text('通过', style: TextStyle(color: AppTheme.green, fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
              if (isReimbursement && status == 'approved') ...[
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    onPressed: () => _approve(id, 'paid'),
                    icon: const Icon(Icons.payment, size: 16, color: AppTheme.green),
                    label: const Text('标记已支付', style: TextStyle(color: AppTheme.green, fontSize: 13)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ]),
              ],

              if (!isReimbursement) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _edit(e),
                      icon: Icon(Icons.edit_outlined, size: 16, color: isDark ? Colors.white54 : Colors.black45),
                      label: Text('编辑', style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black45)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _delete(id),
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                      label: const Text('删除', style: TextStyle(color: Colors.red, fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
