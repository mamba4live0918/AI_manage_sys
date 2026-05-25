import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../widgets/watermark.dart';
import '../../providers/auth_provider.dart';

class PermissionsPage extends ConsumerStatefulWidget {
  const PermissionsPage({super.key});

  @override
  ConsumerState<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends ConsumerState<PermissionsPage> {
  final _api = ApiClient();
  final _resourceIdCtrl = TextEditingController();
  List<Map<String, dynamic>> _perms = [];
  bool _loading = false;

  Future<void> _search() async {
    final rid = _resourceIdCtrl.text.trim();
    if (rid.isEmpty) return;
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/permissions/resource/$rid');
      setState(() => _perms = List<Map<String, dynamic>>.from(resp.data['items']));
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _grant() async {
    final rid = _resourceIdCtrl.text.trim();
    if (rid.isEmpty) return;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        String gType = 'role';
        String gValue = 'general';
        String action = 'preview';
        return AlertDialog(
          title: const Text('授予权限'),
          content: StatefulBuilder(
            builder: (_, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  initialValue: gType,
                  decoration: const InputDecoration(labelText: '授权类型'),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('用户')),
                    DropdownMenuItem(value: 'role', child: Text('角色')),
                    DropdownMenuItem(value: 'department', child: Text('部门')),
                    DropdownMenuItem(value: 'project', child: Text('项目')),
                  ],
                  onChanged: (v) => setDialogState(() => gType = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: '授权值', hintText: '用户ID/角色名/部门名'),
                  onChanged: (v) => gValue = v,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField(
                  initialValue: action,
                  decoration: const InputDecoration(labelText: '操作'),
                  items: const [
                    DropdownMenuItem(value: 'preview', child: Text('预览')),
                    DropdownMenuItem(value: 'download', child: Text('下载')),
                    DropdownMenuItem(value: 'edit', child: Text('编辑')),
                    DropdownMenuItem(value: 'admin', child: Text('管理')),
                  ],
                  onChanged: (v) => setDialogState(() => action = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {'grantee_type': gType, 'grantee_value': gValue, 'action': action}),
              child: const Text('授予'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _api.dio.post('/permissions/grant', data: {
        'resource_type': 'file',
        'resource_id': rid,
        ...result,
      });
      _search();
    }
  }

  Future<void> _revoke(String permId) async {
    await _api.dio.delete('/permissions/revoke/$permId');
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _resourceIdCtrl,
                    decoration: const InputDecoration(
                      labelText: '资源ID（文件/文件夹UUID）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _search, child: const Text('查询权限')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: auth.user?.isAdmin == true ? _grant : null, child: const Text('+ 授予')),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _perms.isEmpty
                      ? const Center(child: Text('输入资源ID查询现有权限', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: _perms.length,
                          itemBuilder: (_, i) {
                            final p = _perms[i];
                            return ListTile(
                              leading: const Icon(Icons.rule),
                              title: Text('${p['grantee_type']}: ${p['grantee_value']}'),
                              subtitle: Text(p['action'] ?? ''),
                              trailing: auth.user?.isAdmin == true
                                  ? IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _revoke(p['id']),
                                    )
                                  : null,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
