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
                  // ── Suppliers (Table) ──
                  _suppliers.isEmpty
                      ? Center(child: Text('暂无供应商', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                      : Column(children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Table(
                                columnWidths: const {
                                  0: FlexColumnWidth(1.2), // 名称
                                  1: FlexColumnWidth(1.5), // 专长
                                  2: FlexColumnWidth(1.5), // 联系方式
                                  3: FlexColumnWidth(1.0), // 日期
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
                                      _TableHeader('名称'),
                                      _TableHeader('专长'),
                                      _TableHeader('联系方式'),
                                      _TableHeader('日期'),
                                    ],
                                  ),
                                  // Data rows
                                  ..._pagedSuppliers.map((s) {
                                    final name = s['name'] as String? ?? '';
                                    final expertise = (s['expertise'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
                                    final contact = [s['contact_person'] as String? ?? '', s['contact_phone'] as String? ?? ''].where((x) => x.isNotEmpty).join(' · ');
                                    final date = s['created_at'] as String? ?? '';
                                    final type = s['type'] as String? ?? 'company';
                                    return TableRow(
                                      children: [
                                        // Name
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
                                        // Expertise
                                        _TableCell(
                                          Text(expertise.isNotEmpty ? expertise.join(' · ') : '-', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          isDark: isDark,
                                        ),
                                        // Contact
                                        _TableCell(
                                          Text(contact.isNotEmpty ? contact : '-', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          isDark: isDark,
                                        ),
                                        // Date
                                        _TableCell(
                                          Text(date.length >= 10 ? date.substring(0, 10) : date, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                                          isDark: isDark,
                                        ),
                                      ],
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          // Supplier pagination
                          if (_supplierTotalPages > 1)
                            Container(
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
                            ),
                        ]),

                  // ── Instructors (keep ListView) ──
                  _instructors.isEmpty
                      ? Center(child: Text('暂无讲师', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _instructors.length,
                          itemBuilder: (_, i) {
                            final inst = _instructors[i];
                            final expertise = (inst['expertise'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.purple.withAlpha(20),
                                  child: const Icon(Icons.person_rounded, color: AppTheme.purple, size: 20),
                                ),
                                title: Text(inst['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(expertise.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (((inst['rating'] as num?)?.toDouble() ?? 0) > 0)
                                    Row(children: [
                                      const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                                      Text('${inst['rating']}', style: const TextStyle(fontSize: 12)),
                                      const SizedBox(width: 8),
                                    ]),
                                  const Icon(Icons.chevron_right_rounded, size: 18),
                                ]),
                              ),
                            );
                          },
                        ),
                ],
              ),
      ),

      // ── Bottom create buttons ──
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
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
        ]),
      ),
    ]);
  }
}
