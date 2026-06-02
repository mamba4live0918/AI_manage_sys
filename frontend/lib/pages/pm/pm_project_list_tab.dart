import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _stageNames = {
  'initiation': '启动', 'planning': '规划', 'execution': '执行',
  'monitoring': '监控', 'closure': '收尾',
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

class PmProjectListTab extends StatefulWidget {
  final void Function(String projectId)? onProjectSelected;
  const PmProjectListTab({super.key, this.onProjectSelected});

  @override
  State<PmProjectListTab> createState() => _PmProjectListTabState();
}

class _PmProjectListTabState extends State<PmProjectListTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _stageFilter = '';
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{'limit': 100};
      if (_stageFilter.isNotEmpty) params['stage'] = _stageFilter;
      final resp = await _api.dio.get('/pm/projects', queryParameters: params);
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp.data['items']);
        _page = 0;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确定要删除"$name"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/pm/projects/$id');
      _load();
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    String stage = 'initiation';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建项目'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '项目名称 *')),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '描述')),
              const SizedBox(height: 8),
              TextField(controller: budgetCtrl, decoration: const InputDecoration(labelText: '预算'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '阶段'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: stage, isExpanded: true, isDense: true,
                    items: _stageNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDlg(() => stage = v!),
                  ),
                ),
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
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/pm/projects', data: {
      'name': nameCtrl.text.trim(),
      'description': descCtrl.text.trim(),
      'budget': double.tryParse(budgetCtrl.text) ?? 0.0,
      'stage': stage,
    });
    _load();
  }

  // ── Responsive: table layout ──
  Widget _buildProjectTable(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(1.5),
          1: FlexColumnWidth(2.0),
          2: FlexColumnWidth(0.8),
          3: FlexColumnWidth(1.2),
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
              _TableHeader('描述'),
              _TableHeader('阶段'),
              _TableHeader('日期'),
            ],
          ),
          ..._pagedItems.map((p) {
            final id = p['id'] as String;
            final name = p['name'] as String? ?? '';
            final desc = p['description'] as String? ?? '';
            final stage = p['stage'] as String? ?? 'initiation';
            final date = p['created_at'] as String? ?? '';
            return TableRow(
              children: [
                _TableCell(
                  Row(children: [
                    const Icon(Icons.engineering_rounded, size: 16, color: AppTheme.blue),
                    const SizedBox(width: 6),
                    Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                  ]),
                  isDark: isDark,
                  onTap: () => widget.onProjectSelected?.call(id),
                ),
                _TableCell(
                  Text(desc, style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  isDark: isDark,
                  onTap: () => widget.onProjectSelected?.call(id),
                ),
                _TableCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.blue.withAlpha(isDark ? 25 : 15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_stageNames[stage] ?? stage, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.blue)),
                  ),
                  isDark: isDark,
                  onTap: () => widget.onProjectSelected?.call(id),
                ),
                _TableCell(
                  Row(children: [
                    Text(
                      date.length >= 10 ? date.substring(0, 10) : date,
                      style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                    ),
                    const Spacer(),
                    Tooltip(
                      message: '删除',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _delete(id, name),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline, size: 16, color: AppTheme.red.withAlpha(isDark ? 180 : 200)),
                        ),
                      ),
                    ),
                  ]),
                  isDark: isDark,
                  onTap: () => widget.onProjectSelected?.call(id),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Responsive: card layout ──
  Widget _buildProjectCards(bool isDark) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 500 ? 2 : 1;
        final cardWidth = (w - 12 * (cols + 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _pagedItems)
              SizedBox(
                width: cardWidth,
                child: _buildProjectCard(p, isDark),
              ),
          ]),
        );
      },
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> p, bool isDark) {
    final id = p['id'] as String;
    final name = p['name'] as String? ?? '';
    final desc = p['description'] as String? ?? '';
    final stage = p['stage'] as String? ?? 'initiation';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onProjectSelected?.call(id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppTheme.blue)),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Material(
              color: AppTheme.red.withAlpha(isDark ? 20 : 15),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _delete(id, name),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.delete_outline, size: 13, color: AppTheme.red),
                    const SizedBox(width: 4),
                    Text('删除', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.red)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: AppTheme.blue.withAlpha(isDark ? 25 : 18),
                border: Border.all(color: AppTheme.blue.withAlpha(isDark ? 100 : 60)),
              ),
              child: Text(_stageNames[stage] ?? stage, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.blue)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(desc, style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ]),
      ),
    );
  }

  // ── Pagination bar ──
  Widget _buildPagination(bool isDark) {
    if (_totalPages <= 1) return const SizedBox.shrink();
    return Container(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Column(children: [
      // ── Create button ──
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(height: 40, child: ElevatedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建项目'),
            )),
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
          Text('项目管理', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('›', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
          Text('项目列表', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
        ]),
      ),

      // ── Stage filter chips ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', ..._stageNames.keys].map((s) {
            final selected = _stageFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s.isEmpty ? '全部' : _stageNames[s] ?? s),
                selected: selected,
                onSelected: (_) { _stageFilter = selected ? '' : s; _load(); },
              ),
            );
          }).toList()),
        ),
      ),

      const SizedBox(height: 4),

      // ── Content ──
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_items.isEmpty)
        Expanded(child: Center(child: Text('暂无项目', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120)))))
      else
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 800) {
                return _buildProjectTable(isDark);
              }
              return _buildProjectCards(isDark);
            },
          ),
        ),

      // ── Pagination ──
      _buildPagination(isDark),
    ]);
  }
}
