import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class PmVisitLogTab extends StatefulWidget {
  final String? projectId;
  const PmVisitLogTab({super.key, this.projectId});

  @override
  State<PmVisitLogTab> createState() => _PmVisitLogTabState();
}

class _PmVisitLogTabState extends State<PmVisitLogTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.projectId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final projects = await _api.dio.get('/pm/projects', queryParameters: {'limit': 100});
      setState(() {
        _projects = List<Map<String, dynamic>>.from(projects.data['items']);
      });
      if (_selectedProjectId != null) {
        final logs = await _api.dio.get('/pm/projects/$_selectedProjectId/logs', queryParameters: {'limit': 50});
        setState(() { _logs = List<Map<String, dynamic>>.from(logs.data['items']); });
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final contentCtrl = TextEditingController();
    final locationCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建走访日志'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: '地点')),
            const SizedBox(height: 8),
            TextField(controller: contentCtrl, maxLines: 4, decoration: const InputDecoration(labelText: '内容')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || _selectedProjectId == null) return;

    await _api.dio.post('/pm/projects/$_selectedProjectId/logs', data: {
      'content': contentCtrl.text.trim(),
      'location': locationCtrl.text.trim(),
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: InputDecorator(
              decoration: const InputDecoration(labelText: '项目', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedProjectId,
                  isExpanded: true, isDense: true,
                  hint: const Text('选择项目'),
                  items: _projects.map((p) => DropdownMenuItem(
                    value: p['id'] as String?,
                    child: Text(p['name'] as String? ?? '', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) { _selectedProjectId = v; _load(); },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(height: 40, child: ElevatedButton.icon(
            onPressed: _selectedProjectId != null ? _create : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新增'),
          )),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _selectedProjectId == null
                ? Center(child: Text('请选择一个项目', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : _logs.isEmpty
                    ? Center(child: Text('暂无走访日志', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _logs.length,
                        itemBuilder: (_, i) {
                          final l = _logs[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.accent.withAlpha(isDark ? 25 : 15),
                                child: const Icon(Icons.location_on_rounded, color: AppTheme.blue, size: 20),
                              ),
                              title: Text(l['location'] as String? ?? '', maxLines: 1),
                              subtitle: Text(l['content'] as String? ?? '', maxLines: 2),
                              trailing: Text((l['visited_at'] as String? ?? '').substring(0, 10), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(100))),
                            ),
                          );
                        },
                      ),
      ),
    ]);
  }
}
