import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _unassigned = [];
  final Set<String> _expandedDeptIds = {};
  bool _loading = true;

  static const _roleNames = {
    'admin': '管理员',
    'dept_manager': '部门经理',
    'project_manager': '项目经理',
    'general': '普通用户',
  };
  static const _roleColors = {
    'admin': AppTheme.red,
    'dept_manager': Colors.orange,
    'project_manager': AppTheme.blue,
    'general': AppTheme.green,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/auth/users');
      setState(() {
        _departments =
            List<Map<String, dynamic>>.from(resp.data['departments'] ?? []);
        _unassigned =
            List<Map<String, dynamic>>.from(resp.data['unassigned'] ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _toggleExpand(String deptId) {
    setState(() {
      if (_expandedDeptIds.contains(deptId)) {
        _expandedDeptIds.remove(deptId);
      } else {
        _expandedDeptIds.add(deptId);
      }
    });
  }

  static const _allModuleLabels = {
    'dashboard': '首页',
    'files': '文件',
    'ip': '讲师IP',
    'audit': '审计',
    'users': '用户管理',
    'marketing': '市场部',
    'bidding': '招投标',
  };

  Color _roleColor(String role) => _roleColors[role] ?? AppTheme.blue;
  String _roleName(String role) => _roleNames[role] ?? role;

  // ── Actions ──

  Future<void> _createDepartment() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final selModules = <String>['dashboard', 'files'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('新建部门'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '部门名称'),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: '描述（可选）'),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('可访问模块', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                ..._allModuleLabels.entries.map((e) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(e.value, style: const TextStyle(fontSize: 14)),
                  value: selModules.contains(e.key),
                  onChanged: (v) => setDlg(() {
                    if (v == true) { selModules.add(e.key); } else { selModules.remove(e.key); }
                  }),
                )),
              ],
            ),
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
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await _api.dio.post('/departments', data: {
          'name': nameCtrl.text.trim(),
          'description': descCtrl.text.trim(),
          'accessible_modules': selModules,
        });
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('创建失败: $e')));
        }
      }
    }
  }

  Future<void> _editDepartment(Map<String, dynamic> dept) async {
    final nameCtrl = TextEditingController(text: dept['name'] ?? '');
    final descCtrl = TextEditingController(text: dept['description'] ?? '');
    final selModules = List<String>.from(dept['accessible_modules'] ?? []);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('编辑部门'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '部门名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: '描述'),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('可访问模块', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                ..._allModuleLabels.entries.map((e) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(e.value, style: const TextStyle(fontSize: 14)),
                  value: selModules.contains(e.key),
                  onChanged: (v) => setDlg(() {
                    if (v == true) { selModules.add(e.key); } else { selModules.remove(e.key); }
                  }),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _api.dio.put('/departments/${dept['id']}', data: {
        'name': nameCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'accessible_modules': selModules,
      });
      _load();
    }
  }

  Future<void> _editUserModules(Map<String, dynamic> ud) async {
    final selModules = List<String>.from(ud['extra_modules'] ?? []);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('额外模块权限 — ${ud['username']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('跨部门临时访问权限（叠加到部门默认模块）',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                ..._allModuleLabels.entries.map((e) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(e.value, style: const TextStyle(fontSize: 14)),
                  value: selModules.contains(e.key),
                  onChanged: (v) => setDlg(() {
                    if (v == true) { selModules.add(e.key); } else { selModules.remove(e.key); }
                  }),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _api.dio.patch('/auth/users/${ud['id']}/modules', data: {
        'extra_modules': selModules,
      });
      _load();
    }
  }

  Future<void> _deleteDepartment(String deptId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除部门'),
        content: Text('确定删除"$name"？成员将变为未安排。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api.dio.delete('/departments/$deptId');
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  Future<void> _setLeader(String deptId, String deptName) async {
    final dept = _departments.firstWhere((d) => d['id'] == deptId);
    final members = List<Map<String, dynamic>>.from(dept['members'] ?? []);
    if (members.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('部门没有成员，请先添加成员')));
      }
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('设置部门长 — $deptName'),
        children: [
          for (final m in members)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m['id'] as String),
              child: Row(
                children: [
                  _Avatar(
                      username: m['username'] ?? '',
                      color: _roleColor(m['role'] ?? '')),
                  const SizedBox(width: 12),
                  Text(m['username'] ?? ''),
                  const Spacer(),
                  Text(_roleName(m['role'] ?? ''),
                      style: TextStyle(
                          fontSize: 12,
                          color: _roleColor(m['role'] ?? ''))),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      try {
        await _api.dio
            .patch('/departments/$deptId/leader', data: {'leader_id': selected});
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('设置失败: $e')));
        }
      }
    }
  }

  Future<void> _addMember(String deptId) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('添加成员 — 选择用户'),
        children: [
          for (final u in _unassigned)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, u['id'] as String),
              child: Row(
                children: [
                  _Avatar(
                      username: u['username'] ?? '',
                      color: _roleColor(u['role'] ?? '')),
                  const SizedBox(width: 12),
                  Text(u['username'] ?? ''),
                  const Spacer(),
                  Text(_roleName(u['role'] ?? ''),
                      style: TextStyle(
                          fontSize: 12,
                          color: _roleColor(u['role'] ?? ''))),
                ],
              ),
            ),
          if (_unassigned.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('没有未安排的用户', style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
    if (selected != null) {
      try {
        await _api.dio
            .post('/departments/$deptId/members', data: {'user_id': selected});
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('添加失败: $e')));
        }
      }
    }
  }

  Future<void> _removeMember(String deptId, String userId) async {
    try {
      await _api.dio.delete('/departments/$deptId/members/$userId');
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('移除失败: $e')));
      }
    }
  }

  Future<void> _changeRole(
      String userId, String username, String currentRole) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('修改角色 — $username'),
        children: [
          for (final role in _roleNames.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, role.key),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _roleColor(role.key),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(role.value),
                  const Spacer(),
                  if (role.key == currentRole)
                    const Icon(Icons.check_rounded,
                        size: 18, color: AppTheme.blue),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null && selected != currentRole) {
      try {
        await _api.dio
            .patch('/auth/users/$userId/role', data: {'role': selected});
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('修改失败: $e')));
        }
      }
    }
  }

  Future<void> _deleteUser(String userId, String username) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除用户'),
        content: Text('确定删除用户"$username"？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api.dio.delete('/auth/users/$userId');
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  Future<void> _addToDept(String userId, String username) async {
    final deptId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('将 $username 添加到...'),
        children: [
          for (final d in _departments)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d['id']),
              child: Row(
                children: [
                  const Icon(Icons.group_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(d['name'] ?? ''),
                ],
              ),
            ),
        ],
      ),
    );
    if (deptId != null) {
      try {
        await _api.dio
            .post('/departments/$deptId/members', data: {'user_id': userId});
        _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('添加失败: $e')));
        }
      }
    }
  }

  void _showAddUserDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'general';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建用户'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: '邮箱'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: '角色'),
                items: _roleNames.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setDialogState(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty ||
                    emailCtrl.text.isEmpty ||
                    passCtrl.text.length < 6) {
                  return;
                }
                try {
                  await _api.dio.post('/auth/users', data: {
                    'username': nameCtrl.text,
                    'email': emailCtrl.text,
                    'password': passCtrl.text,
                    'role': role,
                  });
                  Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text('创建失败: $e')));
                  }
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(text,
            style: TextStyle(
              color: (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black)
                  .withAlpha(80),
              fontSize: 14,
            )),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isAdmin = auth.user?.role == 'admin';

    if (!isAdmin) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: Text('仅管理员可访问')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('用户管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            tooltip: '添加用户',
            onPressed: _showAddUserDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    sliver: SliverToBoxAdapter(
                      child: _buildUnassignedCard(isDark),
                    ),
                  ),
                  if (_departments.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                      sliver: SliverToBoxAdapter(
                        child: Text('部门/小组',
                            style: theme.textTheme.titleMedium),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DepartmentCard(
                            dept: _departments[i],
                            isExpanded:
                                _expandedDeptIds.contains(_departments[i]['id']),
                            isDark: isDark,
                            roleColor: _roleColor,
                            roleName: _roleName,
                            onToggle: () =>
                                _toggleExpand(_departments[i]['id']),
                            onSetLeader: () => _setLeader(
                                _departments[i]['id'],
                                _departments[i]['name']),
                            onAddMember: () =>
                                _addMember(_departments[i]['id']),
                            onDeleteDept: () => _deleteDepartment(
                                _departments[i]['id'],
                                _departments[i]['name']),
                            onEditDept: () => _editDepartment(_departments[i]),
                            onRemoveMember: (uid) => _removeMember(
                                _departments[i]['id'], uid),
                            onChangeRole: _changeRole,
                            onDeleteUser: _deleteUser,
                            onEditUserModules: _editUserModules,
                          ),
                        ),
                        childCount: _departments.length,
                      ),
                    ),
                  ),
                  if (_departments.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverToBoxAdapter(
                        child: _emptyHint('暂无部门，点击下方按钮创建'),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    sliver: SliverToBoxAdapter(
                      child: SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _createDepartment,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('新建部门'),
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                ],
              ),
            ),
    );
  }

  Widget _buildUnassignedCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Text('未安排',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: (isDark ? Colors.white : Colors.black)
                          .withAlpha(180),
                    )),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey.withAlpha(20),
                  ),
                  child: Text('${_unassigned.length}人',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          if (_unassigned.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text('暂无未安排人员',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            )
          else
            ..._unassigned.map((u) => _UserRow(
                  user: u,
                  isDark: isDark,
                  roleColor: _roleColor,
                  roleName: _roleName,
                  onChangeRole: (uid, uname, role) =>
                      _changeRole(uid, uname, role),
                  onDeleteUser: (uid, uname) => _deleteUser(uid, uname),
                  onEditModules: () => _editUserModules(u),
                  onAddToDept: _departments.isNotEmpty
                      ? () => _addToDept(u['id'], u['username'])
                      : null,
                )),
        ],
      ),
    );
  }
}

// ── Department card ──

class _DepartmentCard extends StatelessWidget {
  final Map<String, dynamic> dept;
  final bool isExpanded;
  final bool isDark;
  final Color Function(String) roleColor;
  final String Function(String) roleName;
  final VoidCallback onToggle;
  final VoidCallback onSetLeader;
  final VoidCallback onAddMember;
  final VoidCallback onDeleteDept;
  final VoidCallback onEditDept;
  final void Function(String userId) onRemoveMember;
  final void Function(String userId, String username, String role) onChangeRole;
  final void Function(String userId, String username) onDeleteUser;
  final void Function(Map<String, dynamic> user) onEditUserModules;

  const _DepartmentCard({
    required this.dept,
    required this.isExpanded,
    required this.isDark,
    required this.roleColor,
    required this.roleName,
    required this.onToggle,
    required this.onSetLeader,
    required this.onAddMember,
    required this.onDeleteDept,
    required this.onEditDept,
    required this.onRemoveMember,
    required this.onChangeRole,
    required this.onDeleteUser,
    required this.onEditUserModules,
  });

  @override
  Widget build(BuildContext context) {
    final leader = dept['leader'] as Map<String, dynamic>?;
    final members = List<Map<String, dynamic>>.from(dept['members'] ?? []);
    final name = dept['name'] as String? ?? '';
    final memberCount = dept['member_count'] as int? ?? members.length;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 22,
                      color: (isDark ? Colors.white : Colors.black)
                          .withAlpha(120),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.blue.withAlpha(20),
                      ),
                      child: const Icon(Icons.group_rounded,
                          size: 18, color: AppTheme.blue),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.15)),
                          if (leader != null)
                            Text('部门长: ${leader['username']}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: (isDark ? Colors.white : Colors.black)
                                        .withAlpha(100))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppTheme.blue.withAlpha(20),
                      ),
                      child: Text('$memberCount人',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.blue)),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz_rounded,
                          size: 18,
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(100)),
                      onSelected: (v) {
                        switch (v) {
                          case 'edit':
                            onEditDept();
                          case 'leader':
                            onSetLeader();
                          case 'add':
                            onAddMember();
                          case 'delete':
                            onDeleteDept();
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('编辑部门')),
                        const PopupMenuItem(
                            value: 'leader', child: Text('设置部门长')),
                        const PopupMenuItem(
                            value: 'add', child: Text('添加成员')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除部门',
                              style: TextStyle(color: AppTheme.red)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无成员', style: TextStyle(color: Colors.grey)),
              )
            else
              ...members.map((u) => _UserRow(
                    user: u,
                    isDark: isDark,
                    roleColor: roleColor,
                    roleName: roleName,
                    isInDept: true,
                    onChangeRole: onChangeRole,
                    onDeleteUser: onDeleteUser,
                    onEditModules: () => onEditUserModules(u),
                    onRemoveFromDept: () => onRemoveMember(u['id']),
                  )),
          ],
        ],
      ),
    );
  }
}

// ── User row ──

class _UserRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isDark;
  final Color Function(String) roleColor;
  final String Function(String) roleName;
  final bool isInDept;
  final void Function(String userId, String username, String role)?
      onChangeRole;
  final void Function(String userId, String username)? onDeleteUser;
  final VoidCallback? onRemoveFromDept;
  final VoidCallback? onAddToDept;
  final VoidCallback? onEditModules;

  const _UserRow({
    required this.user,
    required this.isDark,
    required this.roleColor,
    required this.roleName,
    this.isInDept = false,
    this.onChangeRole,
    this.onDeleteUser,
    this.onRemoveFromDept,
    this.onAddToDept,
    this.onEditModules,
  });

  @override
  Widget build(BuildContext context) {
    final username = user['username'] as String? ?? '';
    final email = user['email'] as String? ?? '';
    final role = user['role'] as String? ?? 'general';
    final color = roleColor(role);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              _Avatar(username: username, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(username,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.15),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: color.withAlpha(20),
                          ),
                          child: Text(roleName(role),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(email,
                        style: TextStyle(
                            fontSize: 13,
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(100))),
                  ],
                ),
              ),
              if (onChangeRole != null)
                _MiniIconButton(
                  icon: Icons.edit_rounded,
                  tooltip: '修改角色',
                  onTap: () => onChangeRole!(user['id'], username, role),
                ),
              if (onEditModules != null)
                _MiniIconButton(
                  icon: Icons.extension_rounded,
                  tooltip: '额外模块',
                  onTap: onEditModules!,
                  color: AppTheme.purple,
                ),
              if (onAddToDept != null)
                _MiniIconButton(
                  icon: Icons.group_add_rounded,
                  tooltip: '加入部门',
                  onTap: onAddToDept!,
                ),
              if (onRemoveFromDept != null)
                _MiniIconButton(
                  icon: Icons.remove_circle_outline_rounded,
                  tooltip: '移出部门',
                  onTap: onRemoveFromDept!,
                  color: Colors.orange,
                ),
              if (onDeleteUser != null)
                _MiniIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '删除用户',
                  onTap: () => onDeleteUser!(user['id'], username),
                  color: AppTheme.red,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar ──

class _Avatar extends StatelessWidget {
  final String username;
  final Color color;
  const _Avatar({required this.username, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withAlpha(20),
      ),
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ── Mini icon button ──

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ??
        (Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black)
            .withAlpha(120);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: c),
          ),
        ),
      ),
    );
  }
}
