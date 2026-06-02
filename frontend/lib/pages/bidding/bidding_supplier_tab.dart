import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

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

class BiddingSupplierTab extends StatefulWidget {
  const BiddingSupplierTab({super.key});

  @override
  State<BiddingSupplierTab> createState() => _BiddingSupplierTabState();
}

class _BiddingSupplierTabState extends State<BiddingSupplierTab>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  late final TabController _tabCtrl;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _instructors = [];
  bool _loading = true;

  // Supplier pagination
  int _supplierPage = 0;
  static const int _supplierPageSize = 20;

  List<Map<String, dynamic>> get _pagedSuppliers {
    final start = _supplierPage * _supplierPageSize;
    final end = start + _supplierPageSize;
    if (start >= _suppliers.length) return [];
    return _suppliers.sublist(start, end > _suppliers.length ? _suppliers.length : end);
  }

  int get _supplierTotalPages => (_suppliers.length / _supplierPageSize).ceil();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final sResp = await _api.dio.get('/bidding/suppliers', queryParameters: {'limit': 100});
      final iResp = await _api.dio.get('/bidding/instructors', queryParameters: {'limit': 100});
      setState(() {
        _suppliers = List<Map<String, dynamic>>.from(sResp.data['items']);
        _instructors = List<Map<String, dynamic>>.from(iResp.data['items']);
        _supplierPage = 0;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _createSupplier() async {
    final nameCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String type = 'company';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建供应商'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称 *')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '类型'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: type, isExpanded: true, isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'company', child: Text('公司')),
                      DropdownMenuItem(value: 'individual', child: Text('个人')),
                      DropdownMenuItem(value: 'agency', child: Text('代理机构')),
                    ],
                    onChanged: (v) => setDlg(() => type = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: '联系人')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '联系电话')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/bidding/suppliers', data: {
      'name': nameCtrl.text.trim(),
      'type': type,
      'contact_person': contactCtrl.text.trim(),
      'contact_phone': phoneCtrl.text.trim(),
    });
    _load();
  }

  Future<void> _createInstructor() async {
    final nameCtrl = TextEditingController();
    final expertiseCtrl = TextEditingController();
    String? supplierId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建讲师'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名 *')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '所属供应商 (可选)'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: supplierId,
                    isExpanded: true, isDense: true,
                    hint: const Text('不关联供应商'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('不关联')),
                      ..._suppliers.map((s) => DropdownMenuItem(
                        value: s['id'] as String?,
                        child: Text(s['name'] as String? ?? ''),
                      )),
                    ],
                    onChanged: (v) => setDlg(() => supplierId = v),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: expertiseCtrl, decoration: const InputDecoration(labelText: '专长 (逗号分隔)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/bidding/instructors', data: {
      'name': nameCtrl.text.trim(),
      'supplier_id': supplierId,
      'expertise': expertiseCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    });
    _load();
  }

  Future<void> _matchCourse() async {
    final courseCtrl = TextEditingController();
    final reqCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('课程匹配'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: courseCtrl, decoration: const InputDecoration(labelText: '课程名称')),
            const SizedBox(height: 8),
            TextField(controller: reqCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '需求描述')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('匹配')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final resp = await _api.dio.post('/bidding/match-course', data: {
        'course_name': courseCtrl.text.trim(),
        'requirements': reqCtrl.text.trim(),
      });
      if (mounted) {
        final matches = (resp.data['matches'] as List<dynamic>?) ?? [];
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('匹配结果 (模型: ${resp.data['model'] ?? '未知'})'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: matches.isEmpty
                    ? [const Text('无匹配结果')]
                    : matches.map((m) => ListTile(
                        title: Text(m['name'] as String? ?? ''),
                        subtitle: Text(m['reason'] as String? ?? '', maxLines: 3),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: AppTheme.purple.withAlpha(20),
                          ),
                          child: Text('${m['score'] ?? '?'}分', style: const TextStyle(fontSize: 12, color: AppTheme.purple)),
                        ),
                      )).toList(),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('确定'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匹配失败: $e')));
    }
  }

  // ──────────────────── Edit / Delete ────────────────────

  Future<void> _editSupplier(Map<String, dynamic> supplier) async {
    final nameCtrl = TextEditingController(text: supplier['name'] as String? ?? '');
    final contactCtrl = TextEditingController(text: supplier['contact_person'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: supplier['contact_phone'] as String? ?? '');
    String type = supplier['type'] as String? ?? 'company';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('编辑供应商'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称 *')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '类型'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: type, isExpanded: true, isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'company', child: Text('公司')),
                      DropdownMenuItem(value: 'individual', child: Text('个人')),
                      DropdownMenuItem(value: 'agency', child: Text('代理机构')),
                    ],
                    onChanged: (v) => setDlg(() => type = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: contactCtrl, decoration: const InputDecoration(labelText: '联系人')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '联系电话')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.put('/bidding/suppliers/${supplier['id']}', data: {
      'name': nameCtrl.text.trim(),
      'type': type,
      'contact_person': contactCtrl.text.trim(),
      'contact_phone': phoneCtrl.text.trim(),
    });
    _load();
  }

  Future<void> _deleteSupplier(Map<String, dynamic> supplier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除供应商「${supplier['name']}」吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await _api.dio.delete('/bidding/suppliers/${supplier['id']}');
    _load();
  }

  Future<void> _editInstructor(Map<String, dynamic> inst) async {
    final nameCtrl = TextEditingController(text: inst['name'] as String? ?? '');
    final expertiseCtrl = TextEditingController(
      text: ((inst['expertise'] as List<dynamic>?) ?? []).join(', '),
    );
    String? supplierId = inst['supplier_id'] as String?;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('编辑讲师'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名 *')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '所属供应商 (可选)'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: supplierId,
                    isExpanded: true, isDense: true,
                    hint: const Text('不关联供应商'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('不关联')),
                      ..._suppliers.map((s) => DropdownMenuItem(
                        value: s['id'] as String?,
                        child: Text(s['name'] as String? ?? ''),
                      )),
                    ],
                    onChanged: (v) => setDlg(() => supplierId = v),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: expertiseCtrl, decoration: const InputDecoration(labelText: '专长 (逗号分隔)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.put('/bidding/instructors/${inst['id']}', data: {
      'name': nameCtrl.text.trim(),
      'supplier_id': supplierId,
      'expertise': expertiseCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    });
    _load();
  }

  Future<void> _deleteInstructor(Map<String, dynamic> inst) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除讲师「${inst['name']}」吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await _api.dio.delete('/bidding/instructors/${inst['id']}');
    _load();
  }

  // ──────────────────── Supplier Table / Cards ────────────────────

  Widget _buildSupplierTable(bool isDark, Map<String, String> typeLabels) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(1.5),
          3: FlexColumnWidth(1.0),
          4: FlexColumnWidth(0.7),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 0.5),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurfaceAlt : const Color(0xFFF5F5FA),
            ),
            children: const [
              _TableHeader('名称'),
              _TableHeader('专长'),
              _TableHeader('联系方式'),
              _TableHeader('日期'),
              _TableHeader('操作'),
            ],
          ),
          ..._pagedSuppliers.map((s) {
            final name = s['name'] as String? ?? '';
            final expertise = (s['expertise'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
            final contact = [s['contact_person'] as String? ?? '', s['contact_phone'] as String? ?? ''].where((x) => x.isNotEmpty).join(' · ');
            final date = s['created_at'] as String? ?? '';
            final type = s['type'] as String? ?? 'company';
            return TableRow(
              children: [
                _TableCell(
                  Row(children: [
                    Icon(Icons.business_rounded, size: 16, color: AppTheme.purple),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(typeLabels[type] ?? type, style: TextStyle(fontSize: 10, color: AppTheme.purple.withAlpha(150))),
                      ]),
                    ),
                  ]),
                  isDark: isDark,
                ),
                _TableCell(
                  Text(expertise.isNotEmpty ? expertise.join(' · ') : '-', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  isDark: isDark,
                ),
                _TableCell(
                  Text(contact.isNotEmpty ? contact : '-', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  isDark: isDark,
                ),
                _TableCell(
                  Text(date.length >= 10 ? date.substring(0, 10) : date, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                  isDark: isDark,
                ),
                _TableCell(
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Tooltip(
                      message: '编辑',
                      child: IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        onPressed: () => _editSupplier(s),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ),
                    Tooltip(
                      message: '删除',
                      child: IconButton(
                        icon: Icon(Icons.delete_rounded, size: 16, color: Colors.red.withAlpha(180)),
                        onPressed: () => _deleteSupplier(s),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ),
                  ]),
                  isDark: isDark,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSupplierCards(bool isDark, Map<String, String> typeLabels) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 500 ? 2 : 1;
        final cardWidth = (w - 12 * (cols + 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in _pagedSuppliers)
              SizedBox(
                width: cardWidth,
                child: _buildSupplierCard(s, isDark, typeLabels),
              ),
          ]),
        );
      },
    );
  }

  Widget _buildSupplierCard(Map<String, dynamic> s, bool isDark, Map<String, String> typeLabels) {
    final name = s['name'] as String? ?? '';
    final expertise = (s['expertise'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
    final contact = [s['contact_person'] as String? ?? '', s['contact_phone'] as String? ?? ''].where((x) => x.isNotEmpty).join(' · ');
    final date = s['created_at'] as String? ?? '';
    final type = s['type'] as String? ?? 'company';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppTheme.purple)),
            const SizedBox(width: 10),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.purple.withAlpha(isDark ? 30 : 20),
              ),
              child: const Icon(Icons.business_rounded, size: 20, color: AppTheme.purple),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                  ),
                  child: Text(typeLabels[type] ?? type, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                ),
              ]),
            ),
          ]),
          if (expertise.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 13, top: 6),
              child: Text('专长: ${expertise.join(' · ')}', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            ),
          if (contact.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 13, top: 2),
              child: Text('联系: $contact', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            ),
          if (date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 13, top: 2),
              child: Text(date.length >= 10 ? date.substring(0, 10) : date, style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 13),
            child: Row(children: [
              Material(
                color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editSupplier(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.edit_rounded, size: 14, color: AppTheme.purple),
                      const SizedBox(width: 4),
                      const Text('编辑', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppTheme.red.withAlpha(isDark ? 20 : 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _deleteSupplier(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.delete_rounded, size: 14, color: AppTheme.red.withAlpha(isDark ? 200 : 220)),
                      const SizedBox(width: 4),
                      Text('删除', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.red.withAlpha(isDark ? 200 : 220))),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildSupplierPagination(bool isDark) {
    if (_supplierTotalPages <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: _supplierPage > 0 ? () => setState(() => _supplierPage--) : null,
        ),
        Text('${_supplierPage + 1} / $_supplierTotalPages', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: _supplierPage < _supplierTotalPages - 1 ? () => setState(() => _supplierPage++) : null,
        ),
      ]),
    );
  }

  // ──────────────────── Teacher Table / Cards ────────────────────

  Widget _buildTeacherTable(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.2),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(0.8),
          3: FlexColumnWidth(0.6),
        },
        border: TableBorder(
          horizontalInside: BorderSide(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder, width: 0.5),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurfaceAlt : const Color(0xFFF5F5FA),
            ),
            children: const [
              _TableHeader('姓名'),
              _TableHeader('专长'),
              _TableHeader('评分'),
              _TableHeader('操作'),
            ],
          ),
          ..._instructors.map((inst) {
            final name = inst['name'] as String? ?? '';
            final expertise = (inst['expertise'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
            final rating = (inst['rating'] as num?)?.toDouble() ?? 0.0;
            return TableRow(
              children: [
                _TableCell(
                  Row(children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.purple.withAlpha(20),
                      radius: 14,
                      child: const Icon(Icons.person_rounded, color: AppTheme.purple, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  isDark: isDark,
                ),
                _TableCell(
                  Text(expertise.isNotEmpty ? expertise.join(' · ') : '-', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  isDark: isDark,
                ),
                _TableCell(
                  Row(children: [
                    if (rating > 0) ...[
                      const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                    ] else
                      Text('-', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                  ]),
                  isDark: isDark,
                ),
                _TableCell(
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Tooltip(
                      message: '编辑',
                      child: IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        onPressed: () => _editInstructor(inst),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ),
                    Tooltip(
                      message: '删除',
                      child: IconButton(
                        icon: Icon(Icons.delete_rounded, size: 16, color: Colors.red.withAlpha(180)),
                        onPressed: () => _deleteInstructor(inst),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                    ),
                  ]),
                  isDark: isDark,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTeacherCards(bool isDark) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 500 ? 2 : 1;
        final cardWidth = (w - 12 * (cols + 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final inst in _instructors)
              SizedBox(
                width: cardWidth,
                child: _buildTeacherCard(inst, isDark),
              ),
          ]),
        );
      },
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> inst, bool isDark) {
    final name = inst['name'] as String? ?? '无名称';
    final expertise = (inst['expertise'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
    final rating = (inst['rating'] as num?)?.toDouble() ?? 0.0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppTheme.purple)),
            const SizedBox(width: 10),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppTheme.purple.withAlpha(isDark ? 30 : 20),
              ),
              child: const Icon(Icons.person_rounded, color: AppTheme.purple, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                  ),
                  if (rating > 0)
                    Row(children: [
                      const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(rating.toStringAsFixed(1), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                    ]),
                ]),
                if (expertise.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(expertise.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 13),
            child: Row(children: [
              Material(
                color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _editInstructor(inst),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.edit_rounded, size: 14, color: AppTheme.purple),
                      const SizedBox(width: 4),
                      const Text('编辑', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: AppTheme.red.withAlpha(isDark ? 20 : 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _deleteInstructor(inst),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.delete_rounded, size: 14, color: AppTheme.red.withAlpha(isDark ? 200 : 220)),
                      const SizedBox(width: 4),
                      Text('删除', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.red.withAlpha(isDark ? 200 : 220))),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final typeLabels = {'company': '公司', 'individual': '个人', 'agency': '代理'};

    return Column(children: [
      // ── AI course match button ──
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: _matchCourse,
                icon: const Icon(Icons.psychology_rounded, size: 18),
                label: const Text('AI 课程匹配', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ]),
      ),

      // ── Breadcrumb ──
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(children: [
          Text('首页', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
          Text('招投标', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
          Text('供应商师资', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
        ]),
      ),

      // ── TabBar ──
      TabBar(
        controller: _tabCtrl,
        tabs: const [
          Tab(text: '供应商'),
          Tab(text: '讲师'),
        ],
      ),

      // ── Content ──
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabCtrl,
                children: [
                  // ── Suppliers (responsive) ──
                  _suppliers.isEmpty
                      ? Center(child: Text('暂无供应商', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth >= 800) {
                              return Column(children: [
                                Expanded(
                                  child: _buildSupplierTable(isDark, typeLabels),
                                ),
                                _buildSupplierPagination(isDark),
                              ]);
                            } else {
                              return Column(children: [
                                Expanded(
                                  child: _buildSupplierCards(isDark, typeLabels),
                                ),
                                _buildSupplierPagination(isDark),
                              ]);
                            }
                          },
                        ),

                  // ── Instructors (responsive) ──
                  _instructors.isEmpty
                      ? Center(child: Text('暂无讲师', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth >= 800) {
                              return _buildTeacherTable(isDark);
                            } else {
                              return _buildTeacherCards(isDark);
                            }
                          },
                        ),
                ],
              ),
      ),

      // ── Bottom create buttons ──
      Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 600) {
              return Row(children: [
                Expanded(child: SizedBox(height: 38, child: ElevatedButton.icon(
                  onPressed: _createSupplier,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('供应商', style: TextStyle(fontSize: 13)),
                ))),
                const SizedBox(width: 8),
                Expanded(child: SizedBox(height: 38, child: ElevatedButton.icon(
                  onPressed: _createInstructor,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('讲师', style: TextStyle(fontSize: 13)),
                ))),
              ]);
            } else {
              return Column(children: [
                SizedBox(width: double.infinity, height: 38, child: ElevatedButton.icon(
                  onPressed: _createSupplier,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('供应商', style: TextStyle(fontSize: 13)),
                )),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, height: 38, child: ElevatedButton.icon(
                  onPressed: _createInstructor,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('讲师', style: TextStyle(fontSize: 13)),
                )),
              ]);
            }
          },
        ),
      ),
    ]);
  }
}
