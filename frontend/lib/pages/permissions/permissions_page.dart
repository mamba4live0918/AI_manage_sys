import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../widgets/watermark.dart';
import '../../widgets/shimmer.dart';
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
  bool _searched = false;

  Future<void> _search() async {
    final rid = _resourceIdCtrl.text.trim();
    if (rid.isEmpty) return;
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/permissions/resource/$rid');
      setState(() {
        _perms = List<Map<String, dynamic>>.from(resp.data['items']);
        _searched = true;
      });
    } catch (_) {
      setState(() => _searched = true);
    }
    setState(() => _loading = false);
  }

  Future<void> _grant() async {
    final rid = _resourceIdCtrl.text.trim();
    if (rid.isEmpty) return;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String gType = 'role';
        String gValue = 'general';
        String action = 'preview';
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (_, setDialogState) => Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(60) : Colors.black.withAlpha(40),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('授予权限', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                const SizedBox(height: 20),
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
                const SizedBox(height: 14),
                TextField(
                  decoration: const InputDecoration(labelText: '授权值', hintText: '用户ID / 角色名 / 部门名'),
                  onChanged: (v) => gValue = v,
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx,
                        {'grantee_type': gType, 'grantee_value': gValue, 'action': action}),
                    child: const Text('确认授予', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(theme, isDark, auth),
            const SizedBox(height: 8),
            _buildSearchBar(isDark),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const ShimmerList()
                  : !_searched
                      ? _buildEmpty(theme)
                      : _perms.isEmpty
                          ? Center(
                              child: Text('该资源暂无权限记录',
                                  style: TextStyle(fontSize: 17,
                                      color: theme.colorScheme.onSurface.withAlpha(120))),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _perms.length,
                              itemBuilder: (_, i) => _buildPermRow(_perms[i], isDark, auth),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark, dynamic auth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
      child: Row(
        children: [
          Text('权限管理', style: theme.textTheme.headlineLarge),
          const Spacer(),
          if (auth.user?.isAdmin == true)
            SizedBox(
              height: 34,
              child: FilledButton.icon(
                onPressed: _grant,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('授予', style: TextStyle(fontSize: 15)),
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _resourceIdCtrl,
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                hintText: '资源ID（文件/文件夹UUID）',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                fillColor: isDark ? AppTheme.darkElevated : const Color(0xFFE8E8ED),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _search,
              style: FilledButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('查询', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppTheme.blue.withAlpha(15),
            ),
            child: const Icon(Icons.shield_rounded, size: 36, color: AppTheme.blue),
          ),
          const SizedBox(height: 20),
          Text('查询资源权限', style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(120),
          )),
          const SizedBox(height: 6),
          Text('输入资源ID查看现有权限配置', style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(80),
          )),
        ],
      ),
    );
  }

  Widget _buildPermRow(Map<String, dynamic> p, bool isDark, dynamic auth) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: AppTheme.blue.withAlpha(20),
                ),
                child: const Icon(Icons.rule_rounded, color: AppTheme.blue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['grantee_type']}: ${p['grantee_value']}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, height: 1.3),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.blue.withAlpha(15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p['action'] ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.blue, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              if (auth.user?.isAdmin == true)
                GestureDetector(
                  onTap: () => _revoke(p['id']),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppTheme.red.withAlpha(15),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppTheme.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
