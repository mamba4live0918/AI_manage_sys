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

class MarketingCustomerListTab extends StatefulWidget {
  final void Function(String customerId)? onCustomerSelected;
  const MarketingCustomerListTab({super.key, this.onCustomerSelected});

  @override
  State<MarketingCustomerListTab> createState() => _MarketingCustomerListTabState();
}

class _MarketingCustomerListTabState extends State<MarketingCustomerListTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _customers = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final params = <String, dynamic>{'limit': 100};
      if (_search.isNotEmpty) params['search'] = _search;
      if (_statusFilter.isNotEmpty) params['status'] = _statusFilter;
      final resp = await _api.dio.get('/marketing/customers', queryParameters: params);
      setState(() {
        _customers = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除客户'),
        content: Text('确定要删除"$name"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
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
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '客户名称 *')),
              const SizedBox(height: 8),
              TextField(controller: industryCtrl, decoration: const InputDecoration(labelText: '行业')),
              const SizedBox(height: 8),
              TextField(controller: personCtrl, decoration: const InputDecoration(labelText: '联系人')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '联系电话')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '来源'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: source, isExpanded: true, isDense: true,
                    items: _sourceNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDlg(() => source = v!),
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
    final theme = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索客户名称或行业...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                filled: true, fillColor: Colors.grey.withAlpha(15),
              ),
              onChanged: (v) { _search = v; _load(); },
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ]),
      ),
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
                onSelected: (_) { _statusFilter = selected ? '' : s; _load(); },
              ),
            );
          }).toList()),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text('加载失败: $_error', style: TextStyle(color: theme.colorScheme.error)))
                : _customers.isEmpty
                    ? Center(child: Text('暂无客户', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _customers.length,
                        itemBuilder: (_, i) {
                          final c = _customers[i];
                          final id = c['id'] as String;
                          final name = c['name'] as String? ?? '';
                          final industry = c['industry'] as String? ?? '';
                          final contact = c['contact_person'] as String? ?? '';
                          final status = c['status'] as String? ?? 'active';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.purple.withAlpha(20),
                                child: const Icon(Icons.business_rounded, color: AppTheme.purple, size: 20),
                              ),
                              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text([industry, contact].where((s) => s.isNotEmpty).join(' · ')),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color: AppTheme.purple.withAlpha(20),
                                  ),
                                  child: Text(_statusNames[status] ?? status,
                                    style: const TextStyle(fontSize: 11, color: AppTheme.purple)),
                                ),
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                                  onSelected: (action) {
                                    if (action == 'delete') _delete(id, name);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                                  ],
                                ),
                              ]),
                              onTap: () => widget.onCustomerSelected?.call(id),
                            ),
                          );
                        },
                      ),
      ),
    ]);
  }
}
