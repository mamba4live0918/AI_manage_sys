import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _stageNames = {
  'initiation': '启动', 'planning': '规划', 'execution': '执行',
  'monitoring': '监控', 'closure': '收尾',
};

class PmProjectListTab extends StatefulWidget {
  final void Function(String projectId)? onProjectSelected;
  const PmProjectListTab({super.key, this.onProjectSelected});

  @override
  State<PmProjectListTab> createState() => _PmProjectListTabState();
}

class _PmProjectListTabState extends State<PmProjectListTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;
  String _stageFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{'limit': 50};
      if (_stageFilter.isNotEmpty) params['stage'] = _stageFilter;
      final resp = await _api.dio.get('/pm/projects', queryParameters: params);
      setState(() {
        _projects = List<Map<String, dynamic>>.from(resp.data['items']);
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
              label: const Text('新建项目'),
            )),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _projects.isEmpty
                ? Center(child: Text('暂无项目', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _projects.length,
                    itemBuilder: (_, i) {
                      final p = _projects[i];
                      final id = p['id'] as String;
                      final name = p['name'] as String? ?? '';
                      final stage = p['stage'] as String? ?? 'initiation';
                      final budget = p['budget'] as num? ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE8F0FE),
                            child: Icon(Icons.engineering_rounded, color: AppTheme.blue, size: 20),
                          ),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${_stageNames[stage] ?? stage} · \$${budget.toStringAsFixed(0)}'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: AppTheme.blue.withAlpha(20)),
                              child: Text(_stageNames[stage] ?? stage, style: const TextStyle(fontSize: 11, color: AppTheme.blue)),
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
                          onTap: () => widget.onProjectSelected?.call(id),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
