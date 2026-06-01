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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _api.dio.get('/dashboard/stats');
      setState(() {
        _stats = resp.data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _formatStorage(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
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
      case 'upload':
        return '上传';
      case 'download':
        return '下载';
      case 'preview':
        return '预览';
      case 'delete':
        return '删除';
      case 'create_folder':
        return '新建文件夹';
      case 'set_level':
        return '设置级别';
      case 'copy_generate':
        return '文案生成';
      default:
        return action;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'upload':
        return AppTheme.teal;
      case 'download':
        return AppTheme.green;
      case 'preview':
        return AppTheme.blue;
      case 'delete':
        return AppTheme.red;
      case 'create_folder':
        return AppTheme.orange;
      case 'copy_generate':
        return AppTheme.purple;
      default:
        return AppTheme.blue;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'upload':
        return Icons.upload_rounded;
      case 'download':
        return Icons.download_rounded;
      case 'preview':
        return Icons.visibility_rounded;
      case 'delete':
        return Icons.delete_rounded;
      case 'create_folder':
        return Icons.create_new_folder_rounded;
      case 'copy_generate':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.circle_rounded;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case '图片':
        return Icons.photo_rounded;
      case '视频':
        return Icons.movie_rounded;
      case '音频':
        return Icons.music_note_rounded;
      case '文档':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case '图片':
        return AppTheme.green;
      case '视频':
        return AppTheme.purple;
      case '音频':
        return AppTheme.pink;
      case '文档':
        return AppTheme.blue;
      default:
        return AppTheme.orange;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: Colors.red.withAlpha(150)),
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
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('首页', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
          ),
          Text('主首页', style: theme.appBarTheme.titleTextStyle),
          const SizedBox(height: 20),
          _StatCardsRow(theme: theme, isDark: isDark, isDesktop: isDesktop),
          const SizedBox(height: 24),
          _QuickActions(theme: theme, isDark: isDark, isDesktop: isDesktop),
          const SizedBox(height: 24),
          _StorageBreakdown(theme: theme, isDark: isDark),
          const SizedBox(height: 24),
          _RecentActivity(theme: theme, isDark: isDark),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Stat cards row ──

  Widget _StatCardsRow({
    required ThemeData theme,
    required bool isDark,
    required bool isDesktop,
  }) {
    final cards = [
      (
        '总用户',
        _stats?['total_users']?.toString() ?? '0',
        Icons.people_rounded,
        AppTheme.blue,
      ),
      (
        '总文件',
        _stats?['total_files']?.toString() ?? '0',
        Icons.folder_rounded,
        AppTheme.green,
      ),
      (
        '存储用量',
        _formatStorage(_stats?['total_storage_bytes'] ?? 0),
        Icons.cloud_rounded,
        AppTheme.orange,
      ),
      (
        '文案生成',
        _stats?['total_copywriting_generations']?.toString() ?? '0',
        Icons.auto_awesome_rounded,
        AppTheme.purple,
      ),
      (
        '今日操作',
        _stats?['today_operations']?.toString() ?? '0',
        Icons.trending_up_rounded,
        AppTheme.teal,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: [
          for (final card in cards)
            Expanded(child: _StatCard(card: card, isDark: isDark)),
        ].withSpacing(12),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final card in cards)
          SizedBox(
            width: (width - 50) / 2,
            child: _StatCard(card: card, isDark: isDark),
          ),
      ],
    );
  }

  double get width => MediaQuery.of(context).size.width;

  // ── Quick actions ──

  Widget _QuickActions({
    required ThemeData theme,
    required bool isDark,
    required bool isDesktop,
  }) {
    final auth = ref.watch(authProvider);
    final actions = [
      ('上传文件', Icons.upload_rounded, AppTheme.blue, '/files'),
      ('生成文案', Icons.edit_rounded, AppTheme.purple, '/ip'),
      ('审计日志', Icons.schedule_rounded, AppTheme.orange, '/audit'),
      if (auth.user?.role == 'admin')
        ('用户管理', Icons.people_rounded, AppTheme.teal, '/users'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('快捷操作', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final a in actions)
              SizedBox(
                width: isDesktop ? 180 : (width - 50) / 2,
                child: _QuickActionCard(action: a, isDark: isDark),
              ),
          ],
        ),
      ],
    );
  }

  // ── Storage breakdown ──

  Widget _StorageBreakdown({
    required ThemeData theme,
    required bool isDark,
  }) {
    final items = _stats?['storage_by_type'] as List<dynamic>? ?? [];
    final totalBytes = _stats?['total_storage_bytes'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark
            ? Border.all(color: AppTheme.darkBorder, width: 0.5)
            : Border.all(color: AppTheme.lightBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('存储用量分布', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          if (items.isEmpty)
            _emptyHint('暂无文件')
          else
            ...items.map((item) {
              final type = item['type'] as String;
              final count = item['count'] as int;
              final bytes = item['total_bytes'] as int;
              final pct = totalBytes > 0 ? bytes / totalBytes : 0.0;
              final color = _typeColor(type);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(_typeIcon(type), size: 20, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(type,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  )),
                              Text(
                                '${_formatStorage(bytes)} ($count个)',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: (isDark
                                          ? Colors.white
                                          : Colors.black)
                                      .withAlpha(120),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Container(
                              height: 6,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withAlpha(30),
                              child: FractionallySizedBox(
                                widthFactor: pct.clamp(0.0, 1.0),
                                child: Container(color: color),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── Recent activity ──

  Widget _RecentActivity({
    required ThemeData theme,
    required bool isDark,
  }) {
    final items = _stats?['recent_activity'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最近动态', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _emptyHint('暂无最近活动')
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
              border: isDark
                  ? Border.all(color: AppTheme.darkBorder, width: 0.5)
                  : Border.all(color: AppTheme.lightBorder, width: 0.5),
            ),
            child: Column(
              children: items.map((item) {
                final action = item['action'] as String? ?? '';
                final color = _actionColor(action);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(_actionIcon(action),
                                size: 20, color: color),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['resource_name'] as String? ?? '',
                                    style: theme.textTheme.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          color: color.withAlpha(25),
                                        ),
                                        child: Text(
                                          _actionLabel(action),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        item['username'] as String? ?? '',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: (isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withAlpha(100),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _timeAgo(
                                            item['created_at'] as String?),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: (isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withAlpha(80),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black)
                .withAlpha(80),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ── Individual stat card ──

class _StatCard extends StatelessWidget {
  final (String, String, IconData, Color) card;
  final bool isDark;

  const _StatCard({required this.card, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (label, value, icon, color) = card;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark
            ? Border.all(color: AppTheme.darkBorder, width: 0.5)
            : Border.all(color: AppTheme.lightBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: AppTheme.accent),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.2,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: (isDark ? Colors.white : Colors.black).withAlpha(120),
              letterSpacing: -0.15,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick action card ──

class _QuickActionCard extends StatelessWidget {
  final (String, IconData, Color, String) action;
  final bool isDark;

  const _QuickActionCard({required this.action, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color, route) = action;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(route),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: color.withAlpha(isDark ? 20 : 15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: color.withAlpha(25),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper ──

extension _Spacing on List<Widget> {
  List<Widget> withSpacing(double space) {
    if (length < 2) return this;
    return [
      for (int i = 0; i < length; i++)
        ...[
          this[i],
          if (i < length - 1) SizedBox(width: space),
        ],
    ];
  }
}
