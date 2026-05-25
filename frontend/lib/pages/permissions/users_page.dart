import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_logger.dart';

const _roleNames = {
  'admin': '管理员',
  'dept_manager': '部门经理',
  'project_manager': '项目经理',
  'general': '普通用户',
};
const _roleColors = {
  'admin': AppTheme.red,
  'dept_manager': Colors.orange,
  'project_manager': AppTheme.blue,
  'general': AppTheme.green,
};

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/auth/users');
      setState(() => _users = List<Map<String, dynamic>>.from(resp.data['items']));
    } catch (e) {
      appLog('[USERS] load error: $e');
    }
    setState(() => _loading = false);
  }

  Future<void> _changeRole(String userId, String newRole) async {
    try {
      await _api.dio.patch('/auth/users/$userId/role', data: {'role': newRole});
      _load();
    } catch (e) {
      appLog('[USERS] role change error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isAdmin = auth.user?.role == 'admin';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('用户管理'),
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !isAdmin
              ? const Center(child: Text('仅管理员可访问'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _users.length,
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    final role = u['role'] as String? ?? 'general';
                    final roleName = _roleNames[role] ?? role;
                    final roleColor = _roleColors[role] ?? AppTheme.green;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {},
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    color: roleColor.withAlpha(25),
                                  ),
                                  child: Center(
                                    child: Text(
                                      (u['username'] as String? ?? '?')[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: roleColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(u['username'] as String? ?? '', style: const TextStyle(fontSize: 17)),
                                      if (u['email'] != null)
                                        Text(u['email'] as String,
                                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(100))),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  offset: const Offset(0, 32),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: roleColor.withAlpha(25),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: roleColor.withAlpha(120), width: 0.5),
                                    ),
                                    child: Text(roleName, style: TextStyle(fontSize: 12, color: roleColor, fontWeight: FontWeight.w600)),
                                  ),
                                  itemBuilder: (_) => _roleNames.entries.map((e) => PopupMenuItem(
                                    value: e.key,
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Container(
                                        width: 8, height: 8,
                                        decoration: BoxDecoration(color: _roleColors[e.key] ?? AppTheme.green, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(e.value, style: const TextStyle(fontSize: 13)),
                                      if (e.key == role) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.check, size: 14, color: AppTheme.green),
                                      ],
                                    ]),
                                  )).toList(),
                                  onSelected: (r) {
                                    if (r != role) _changeRole(u['id'] as String, r);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
