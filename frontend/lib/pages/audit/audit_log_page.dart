import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import '../../widgets/shimmer.dart';

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
      'preview' => AppTheme.blue,
      'download' => AppTheme.green,
      'upload' => AppTheme.teal,
      'delete' => AppTheme.red,
      'permission_change' => AppTheme.orange,
      _ => Colors.grey,
    };
  }

  String _actionLabel(String action) {
    return switch (action) {
      'preview' => '预览',
      'download' => '下载',
      'upload' => '上传',
      'delete' => '删除',
      'permission_change' => '权限变更',
      _ => action,
    };
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
            _buildHeader(theme, isDark),
            const SizedBox(height: 8),
            _buildFilterChips(theme, isDark),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '$_total 条记录',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                  const Spacer(),
                  _PageDots(
                    page: _page,
                    total: (_total / 50).ceil(),
                    onPrev: _page > 1 ? () { _page--; _load(); } : null,
                    onNext: _page * 50 < _total ? () { _page++; _load(); } : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const ShimmerList()
                  : _logs.isEmpty
                      ? Center(
                          child: Text('暂无记录',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurface.withAlpha(100), fontSize: 17)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _logs.length,
                          itemBuilder: (_, i) => _buildLogItem(_logs[i], isDark),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
      child: Row(
        children: [
          Text('操作审计', style: theme.textTheme.headlineLarge),
        ],
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme, bool isDark) {
    final actions = [null, 'upload', 'download', 'preview', 'delete', 'permission_change'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: actions.map((a) {
          final selected = _filterAction == a;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                _filterAction = a;
                _page = 1;
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.blue
                      : (isDark ? AppTheme.darkElevated : const Color(0xFFE8E8ED)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  a == null ? '全部' : _actionLabel(a),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: selected ? Colors.white : (isDark ? Colors.white.withAlpha(180) : Colors.black.withAlpha(160)),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log, bool isDark) {
    final action = log['action'] ?? '';
    final color = _actionColor(action);
    final success = log['result'] == 'success';

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              // Icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: color.withAlpha(20),
                ),
                child: Icon(
                  success ? Icons.check_circle_rounded : Icons.close_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${log['username'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _actionLabel(action),
                            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      log['resource_name'] ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        color: (isDark ? Colors.white : Colors.black).withAlpha(120),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatTime(log['created_at'] ?? ''),
                style: TextStyle(
                  fontSize: 13,
                  color: (isDark ? Colors.white : Colors.black).withAlpha(100),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

class _PageDots extends StatelessWidget {
  final int page;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _PageDots({
    required this.page,
    required this.total,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DotButton(icon: Icons.chevron_left_rounded, enabled: onPrev != null, onTap: onPrev),
        const SizedBox(width: 2),
        for (int i = 0; i < total && i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: i == page - 1 ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i == page - 1 ? AppTheme.blue : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withAlpha(30)
                  : Colors.black.withAlpha(15)),
            ),
          ),
        ],
        const SizedBox(width: 2),
        _DotButton(icon: Icons.chevron_right_rounded, enabled: onNext != null, onTap: onNext),
      ],
    );
  }
}

class _DotButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _DotButton({required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          color: enabled
              ? AppTheme.blue.withAlpha(15)
              : Colors.transparent,
        ),
        child: Icon(icon, size: 18,
            color: enabled ? AppTheme.blue : Colors.grey.withAlpha(100)),
      ),
    );
  }
}
