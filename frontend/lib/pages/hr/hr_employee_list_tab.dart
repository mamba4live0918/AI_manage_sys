import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _statusNames = {'active': '在职', 'resigned': '离职', 'probation': '试用期'};

class HrEmployeeListTab extends StatefulWidget {
  const HrEmployeeListTab({super.key});

  @override
  State<HrEmployeeListTab> createState() => _HrEmployeeListTabState();
}

class _HrEmployeeListTabState extends State<HrEmployeeListTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _employees = [];
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
      final resp = await _api.dio.get('/hr/employees', queryParameters: params);
      setState(() {
        _employees = List<Map<String, dynamic>>.from(resp.data['items']);
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
        title: const Text('删除员工'),
        content: Text('确定要删除"$name"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/hr/employees/$id');
      _load();
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final positionCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建员工'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '姓名 *')),
            const SizedBox(height: 8),
            TextField(controller: positionCtrl, decoration: const InputDecoration(labelText: '职位')),
            const SizedBox(height: 8),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: '电话')),
            const SizedBox(height: 8),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: '邮箱')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/hr/employees', data: {
      'name': nameCtrl.text.trim(),
      'position': positionCtrl.text.trim(),
      'phone': phoneCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
    });
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
              label: const Text('新建员工'),
            )),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'active', 'probation', 'resigned'].map((s) {
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
            : _employees.isEmpty
                ? Center(child: Text('暂无员工', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _employees.length,
                    itemBuilder: (_, i) {
                      final e = _employees[i];
                      final id = e['id'] as String;
                      final name = e['name'] as String? ?? '';
                      final position = e['position'] as String? ?? '';
                      final status = e['status'] as String? ?? 'active';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE8F5E9),
                            child: Icon(Icons.person_rounded, color: AppTheme.green, size: 20),
                          ),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text([position, e['phone'] ?? '', e['email'] ?? ''].where((s) => s.isNotEmpty).join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: AppTheme.green.withAlpha(20)),
                              child: Text(_statusNames[status] ?? status, style: const TextStyle(fontSize: 11, color: AppTheme.green)),
                            ),
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
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
