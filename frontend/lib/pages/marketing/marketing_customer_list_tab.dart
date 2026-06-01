import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _sourceNames = {
  'referral': '客户推荐',
  'website': '网站',
  'exhibition': '展会',
  'cold_call': '电话陌拜',
  'other': '其他',
};
const _statusNames = {'active': '活跃', 'dormant': '休眠', 'churned': '已流失'};

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
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

class MarketingCustomerListTab extends StatefulWidget {
  final void Function(String customerId)? onCustomerSelected;
  const MarketingCustomerListTab({super.key, this.onCustomerSelected});

  @override
  State<MarketingCustomerListTab> createState() =>
      _MarketingCustomerListTabState();
}

class _MarketingCustomerListTabState extends State<MarketingCustomerListTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _statusFilter = '';
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = <String, dynamic>{'limit': 100};
      if (_search.isNotEmpty) params['search'] = _search;
      if (_statusFilter.isNotEmpty) params['status'] = _statusFilter;
      final resp =
          await _api.dio.get('/marketing/customers', queryParameters: params);
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp.data['items']);
        _page = 0;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除客户'),
        content: Text('确定要删除"$name"吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/marketing/customers/$id');
      _load();
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final industryCtrl = TextEditingController();
    final personCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String source = 'other';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建客户'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '客户名称 *')),
              const SizedBox(height: 8),
              TextField(
                  controller: industryCtrl,
                  decoration: const InputDecoration(labelText: '行业')),
              const SizedBox(height: 8),
              TextField(
                  controller: personCtrl,
                  decoration: const InputDecoration(labelText: '联系人')),
              const SizedBox(height: 8),
              TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: '联系电话')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '来源'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: source,
                    isExpanded: true,
                    isDense: true,
                    items: _sourceNames.entries
                        .map((e) =>
                            DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setDlg(() => source = v!),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    await _api.dio.post('/marketing/customers', data: {
      'name': nameCtrl.text.trim(),
      'industry': industryCtrl.text.trim(),
      'contact_person': personCtrl.text.trim(),
      'contact_phone': phoneCtrl.text.trim(),
      'source': source,
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Column(children: [
      // ── Search bar ──
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索客户名称或行业...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.withAlpha(15),
              ),
              onChanged: (v) {
                _search = v;
                _load();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建', style: TextStyle(fontSize: 14)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
          Text('首页',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary)),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('›',
                  style: TextStyle(fontSize: 12, color: Colors.grey))),
          Text('市场部',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary)),
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('›',
                  style: TextStyle(fontSize: 12, color: Colors.grey))),
          Text('客户管理',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppTheme.darkText : AppTheme.lightText)),
        ]),
      ),

      // ── Status filter chips ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'active', 'dormant', 'churned'].map((s) {
            final selected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s.isEmpty ? '全部' : _statusNames[s] ?? s),
                selected: selected,
                onSelected: (_) {
                  _statusFilter = selected ? '' : s;
                  _load();
                },
              ),
            );
          }).toList()),
        ),
      ),

      const SizedBox(height: 4),

      // ── Content: DataTable ──
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_error != null)
        Expanded(
            child: Center(
                child: Text('加载失败: $_error',
                    style: TextStyle(color: theme.colorScheme.error))))
      else if (_items.isEmpty)
        Expanded(
            child: Center(
                child: Text('暂无客户',
                    style: TextStyle(
                        color: theme.colorScheme.onSurface.withAlpha(120)))))
      else
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2), // 名称
                1: FlexColumnWidth(1.0), // 行业
                2: FlexColumnWidth(1.0), // 联系人
                3: FlexColumnWidth(0.8), // 状态
                4: FlexColumnWidth(1.0), // 日期
                // 5 used for actions, handled inline
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                    width: 0.5),
              ),
              children: [
                // ── Header row ──
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkSurfaceAlt
                        : const Color(0xFFF5F5FA),
                  ),
                  children: const [
                    _TableHeader('名称'),
                    _TableHeader('行业'),
                    _TableHeader('联系人'),
                    _TableHeader('状态'),
                    _TableHeader('日期'),
                  ],
                ),
                // ── Data rows ──
                ..._pagedItems.map((c) {
                  final id = c['id'] as String;
                  final name = c['name'] as String? ?? '';
                  final industry = c['industry'] as String? ?? '';
                  final contact = c['contact_person'] as String? ?? '';
                  final status = c['status'] as String? ?? 'active';
                  final date = c['created_at'] as String? ?? '';
                  return TableRow(
                    children: [
                      // Name
                      _TableCell(
                        Text(name,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppTheme.darkText
                                    : AppTheme.lightText)),
                        isDark: isDark,
                        onTap: () =>
                            widget.onCustomerSelected?.call(id),
                      ),
                      // Industry
                      _TableCell(
                        Text(industry,
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary)),
                        isDark: isDark,
                        onTap: () =>
                            widget.onCustomerSelected?.call(id),
                      ),
                      // Contact
                      _TableCell(
                        Text(contact,
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary)),
                        isDark: isDark,
                        onTap: () =>
                            widget.onCustomerSelected?.call(id),
                      ),
                      // Status
                      _TableCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.purple.withAlpha(isDark ? 25 : 15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_statusNames[status] ?? status,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.purple)),
                        ),
                        isDark: isDark,
                        onTap: () =>
                            widget.onCustomerSelected?.call(id),
                      ),
                      // Date + delete action
                      _TableCell(
                        Row(children: [
                          Text(
                            date.length >= 10 ? date.substring(0, 10) : date,
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.lightTextSecondary),
                          ),
                          const Spacer(),
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _delete(id, name),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(Icons.delete_outline,
                                  size: 16,
                                  color: AppTheme.red.withAlpha(isDark ? 180 : 200)),
                            ),
                          ),
                        ]),
                        isDark: isDark,
                        onTap: () =>
                            widget.onCustomerSelected?.call(id),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),

      // ── Pagination ──
      if (_totalPages > 1)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: _page > 0
                      ? () => setState(() => _page--)
                      : null,
                ),
                Text('${_page + 1} / $_totalPages',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary)),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: _page < _totalPages - 1
                      ? () => setState(() => _page++)
                      : null,
                ),
              ]),
        ),
    ]);
  }
}
