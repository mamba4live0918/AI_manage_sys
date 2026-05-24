import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';

class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _logs = [];
  int _total = 0;
  int _page = 1;
  bool _loading = false;
  String? _filterAction;
  String? _filterUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/audit/logs', queryParameters: {
        'page': _page,
        'page_size': 50,
        if (_filterAction != null) 'action': _filterAction,
        if (_filterUser != null && _filterUser!.isNotEmpty) 'username': _filterUser,
      });
      setState(() {
        _logs = List<Map<String, dynamic>>.from(resp.data['items']);
        _total = resp.data['total'] ?? 0;
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Color _actionColor(String action) {
    return switch (action) {
      'preview' => Colors.blue,
      'download' => Colors.green,
      'upload' => Colors.cyan,
      'delete' => Colors.red,
      'permission_change' => Colors.orange,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '搜索用户',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      _filterUser = v;
                      _page = 1;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    value: _filterAction,
                    decoration: const InputDecoration(labelText: '操作类型', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('全部')),
                      DropdownMenuItem(value: 'preview', child: Text('预览')),
                      DropdownMenuItem(value: 'download', child: Text('下载')),
                      DropdownMenuItem(value: 'upload', child: Text('上传')),
                      DropdownMenuItem(value: 'delete', child: Text('删除')),
                      DropdownMenuItem(value: 'permission_change', child: Text('权限变更')),
                    ],
                    onChanged: (v) {
                      _filterAction = v;
                      _page = 1;
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('共 $_total 条记录', style: TextStyle(color: Colors.grey[600])),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (_, i) {
                      final log = _logs[i];
                      final action = log['action'] ?? '';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _actionColor(action).withValues(alpha: 0.15),
                          child: Icon(Icons.history, color: _actionColor(action), size: 20),
                        ),
                        title: Text(
                          '${log['username']} - $action',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${log['resource_name'] ?? ''}  ${log['created_at'] ?? ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Icon(
                          log['result'] == 'success' ? Icons.check_circle : Icons.cancel,
                          color: log['result'] == 'success' ? Colors.green : Colors.red,
                          size: 18,
                        ),
                      );
                    },
                  ),
          ),
          // Pagination
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _page > 1 ? () { _page--; _load(); } : null,
                ),
                Text('第 $_page 页'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _page * 50 < _total ? () { _page++; _load(); } : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
