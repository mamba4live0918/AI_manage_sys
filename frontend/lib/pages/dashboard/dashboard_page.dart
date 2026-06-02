import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import '../../widgets/shimmer.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final _api = ApiClient();
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await _api.dio.get('/dashboard/stats');
      setState(() { _stats = resp.data; _loading = false; });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  String _formatStorage(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().toUtc().difference(dt);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'upload': return '上传';
      case 'download': return '下载';
      case 'preview': return '预览';
      case 'delete': return '删除';
      case 'create_folder': return '新建文件夹';
      case 'set_level': return '设置级别';
      case 'copy_generate': return '文案生成';
      default: return action;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'upload': return AppTheme.teal;
      case 'download': return AppTheme.green;
      case 'preview': return AppTheme.blue;
      case 'delete': return AppTheme.red;
      case 'create_folder': return AppTheme.orange;
      case 'copy_generate': return AppTheme.purple;
      default: return AppTheme.blue;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'upload': return Icons.upload_rounded;
      case 'download': return Icons.download_rounded;
      case 'preview': return Icons.visibility_rounded;
      case 'delete': return Icons.delete_rounded;
      case 'create_folder': return Icons.create_new_folder_rounded;
      case 'copy_generate': return Icons.auto_awesome_rounded;
      default: return Icons.circle_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case '图片': return AppTheme.green;
      case '视频': return AppTheme.purple;
      case '音频': return AppTheme.pink;
      case '文档': return AppTheme.blue;
      default: return AppTheme.orange;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case '图片': return Icons.photo_rounded;
      case '视频': return Icons.movie_rounded;
      case '音频': return Icons.music_note_rounded;
      case '文档': return Icons.description_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
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
        body: SafeArea(
          child: _loading
              ? const ShimmerList(count: 6)
              : _error != null
                  ? _buildError()
                  : _buildContent(theme, isDark),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.withAlpha(150)),
        const SizedBox(height: 12),
        Text('加载失败', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loadStats,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('重试'),
        ),
      ]),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final wide = w >= 800;
      final pad = wide ? 20.0 : 12.0;

      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            child: Text('主首页', style: theme.appBarTheme.titleTextStyle),
          ),
          const SizedBox(height: 20),
          _StatCardsRow(isDark: isDark, width: w),
          const SizedBox(height: 24),
          _QuickActions(isDark: isDark, width: w),
          const SizedBox(height: 24),
          _StorageBreakdown(theme: theme, isDark: isDark),
          const SizedBox(height: 24),
          _RecentActivity(theme: theme, isDark: isDark),
          const SizedBox(height: 32),
        ]),
      );
    });
  }

  Widget _StatCardsRow({required bool isDark, required double width}) {
    final cards = [
      ('总用户', _stats?['total_users']?.toString() ?? '0', Icons.people_rounded, AppTheme.blue),
      ('总文件', _stats?['total_files']?.toString() ?? '0', Icons.folder_rounded, AppTheme.green),
      ('存储用量', _formatStorage(_stats?['total_storage_bytes'] ?? 0), Icons.cloud_rounded, AppTheme.orange),
      ('文案生成', _stats?['total_copywriting_generations']?.toString() ?? '0', Icons.auto_awesome_rounded, AppTheme.purple),
      ('今日操作', _stats?['today_operations']?.toString() ?? '0', Icons.trending_up_rounded, AppTheme.teal),
    ];

    if (width >= 800) {
      return Row(children: cards.map((c) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: c == cards.first ? 0 : 6, right: c == cards.last ? 0 : 6),
          child: _statCard(c.$1, c.$2, c.$4, isDark),
        ),
      )).toList());
    }
    final cols = width >= 500 ? 2 : 1;
    final cardW = (width - 12 * (cols + 1)) / cols;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in cards)
        SizedBox(width: cardW, child: _statCard(c.$1, c.$2, c.$4, isDark)),
    ]);
  }

  Widget _statCard(String label, String value, Color accent, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: accent)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
        ]),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
      ]),
    );
  }

  Widget _QuickActions({required bool isDark, required double width}) {
    final auth = ref.watch(authProvider);
    final actions = [
      ('上传文件', Icons.upload_rounded, AppTheme.blue, '/files'),
      ('生成文案', Icons.edit_rounded, AppTheme.purple, '/ip'),
      ('审计日志', Icons.schedule_rounded, AppTheme.orange, '/audit'),
      if (auth.user?.role == 'admin')
        ('用户管理', Icons.people_rounded, AppTheme.teal, '/users'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text('快捷操作', style: Theme.of(context).textTheme.titleMedium),
      ),
      if (width >= 600)
        Row(children: actions.map((a) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: a == actions.first ? 0 : 6, right: a == actions.last ? 0 : 6),
            child: _actionCard(a.$1, a.$2, a.$3, a.$4, isDark),
          ),
        )).toList())
      else
        _wrapActions(actions, width, isDark),
    ]);
  }

  Widget _wrapActions(List<(String, IconData, Color, String)> actions, double width, bool isDark) {
    final cols = width >= 400 ? 2 : 1;
    final cardW = (width - 12 * (cols + 1)) / cols;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final a in actions)
        SizedBox(width: cardW, child: _actionCard(a.$1, a.$2, a.$3, a.$4, isDark)),
    ]);
  }

  Widget _actionCard(String label, IconData icon, Color color, String route, bool isDark) {
    return Material(
      color: color.withAlpha(isDark ? 20 : 15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withAlpha(30)),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 10),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }

  Widget _StorageBreakdown({required ThemeData theme, required bool isDark}) {
    final items = _stats?['storage_by_type'] as List<dynamic>? ?? [];
    final totalBytes = _stats?['total_storage_bytes'] as int? ?? 0;
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('存储用量分布', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        ...items.map((item) {
          final type = item['type'] as String;
          final count = item['count'] as int;
          final bytes = item['total_bytes'] as int;
          final pct = totalBytes > 0 ? bytes / totalBytes : 0.0;
          final color = _typeColor(type);
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withAlpha(isDark ? 25 : 18)),
                child: Icon(_typeIcon(type), size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(type, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    Text('${_formatStorage(bytes)} ($count个)', style: theme.textTheme.labelSmall?.copyWith(color: (isDark ? Colors.white : Colors.black).withAlpha(120))),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: (isDark ? Colors.white : Colors.black).withAlpha(15),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _RecentActivity({required ThemeData theme, required bool isDark}) {
    final items = _stats?['recent_activity'] as List<dynamic>? ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('最近动态', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
          border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
          boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
        ),
        child: Column(children: items.map((item) {
          final action = item['action'] as String? ?? '';
          final color = _actionColor(action);
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: color.withAlpha(isDark ? 25 : 18)),
                    child: Icon(_actionIcon(action), size: 20, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item['resource_name'] as String? ?? '', style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: color.withAlpha(25)),
                          child: Text(_actionLabel(action), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                        ),
                        const SizedBox(width: 6),
                        Text(item['username'] as String? ?? '', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                        const Spacer(),
                        Text(_timeAgo(item['created_at'] as String?), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        }).toList()),
      ),
    ]);
  }
}
