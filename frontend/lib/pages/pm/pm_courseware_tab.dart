import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class PmCoursewareTab extends StatefulWidget {
  const PmCoursewareTab({super.key});

  @override
  State<PmCoursewareTab> createState() => _PmCoursewareTabState();
}

class _PmCoursewareTabState extends State<PmCoursewareTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/pm/coursewares', queryParameters: {'limit': 50});
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final titleCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'document');
    final contentCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建课件'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题 *')),
            const SizedBox(height: 8),
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: '类型')),
            const SizedBox(height: 8),
            TextField(controller: contentCtrl, maxLines: 6, decoration: const InputDecoration(labelText: '内容 (Markdown)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/pm/coursewares', data: {
      'title': titleCtrl.text.trim(),
      'type': typeCtrl.text.trim(),
      'content': contentCtrl.text.trim(),
    });
    _load();
  }

  Future<void> _delete(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课件'),
        content: Text('确定要删除"$title"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/pm/coursewares/$id');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(height: 40, child: ElevatedButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('新建课件'),
        )),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(child: Text('暂无课件', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final c = _items[i];
                      final id = c['id'] as String;
                      final title = c['title'] as String? ?? '';
                      final type = c['type'] as String? ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFFCE4EC),
                            child: Icon(Icons.menu_book_rounded, color: AppTheme.red, size: 20),
                          ),
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$type · v${c['version']}', maxLines: 1),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 18),
                            onSelected: (action) {
                              if (action == 'delete') _delete(id, title);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                            ],
                          ),
                          onTap: () async {
                            final resp = await _api.dio.get('/pm/coursewares/$id');
                            if (mounted) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(resp.data['title'] ?? ''),
                                  content: SizedBox(
                                    width: double.maxFinite,
                                    height: 400,
                                    child: SingleChildScrollView(
                                      child: SelectableText(resp.data['content'] as String? ?? ''),
                                    ),
                                  ),
                                  actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
