import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import '../../widgets/shimmer.dart';
import '../../utils/app_logger.dart';

class FileListPage extends ConsumerStatefulWidget {
  const FileListPage({super.key});

  @override
  ConsumerState<FileListPage> createState() => _FileListPageState();
}

class _FileListPageState extends ConsumerState<FileListPage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _parentId;
  final _parentStack = <String?>[];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/files/list', queryParameters: {
        if (_parentId != null) 'parent_id': _parentId,
      });
      setState(() => _items = List<Map<String, dynamic>>.from(resp.data['items']));
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _navigateTo(String? parentId) {
    _parentStack.add(_parentId);
    _parentId = parentId;
    _loadFiles();
  }

  void _goBack() {
    if (_parentStack.isNotEmpty) {
      _parentId = _parentStack.removeLast();
      _loadFiles();
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result?.files.single.bytes != null) {
      final file = result!.files.single;
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
        if (_parentId != null) 'parent_id': _parentId,
      });
      try {
        await _api.dio.post('/files/upload', data: formData);
        _loadFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('上传失败: $e')));
        }
      }
    }
  }

  Future<void> _deleteFile(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除 "$name" 吗？\n此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/files/$id');
      _loadFiles();
    }
  }

  void _openPreview(String fileId) {
    context.go('/files/preview/$fileId');
  }

  Future<void> _downloadFile(String id, String name) async {
    try {
      String? dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择保存文件夹',
      );
      if (dir == null) return;

      final savePath = '$dir/$name';
      appLog('[DOWNLOAD] saving to: $savePath');

      await _api.dio.download('/preview/download/$id', savePath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载: $name')),
        );
      }
    } catch (e) {
      appLog('[DOWNLOAD] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  IconData _fileIcon(String mime, bool isFolder) {
    if (isFolder) return Icons.folder_rounded;
    if (mime.startsWith('image/')) return Icons.photo_rounded;
    if (mime.startsWith('audio/')) return Icons.music_note_rounded;
    if (mime.startsWith('video/')) return Icons.movie_rounded;
    if (mime.contains('pdf')) return Icons.document_scanner_rounded;
    if (mime.contains('word') || mime.contains('document')) return Icons.description_rounded;
    if (mime.contains('excel') || mime.contains('sheet')) return Icons.table_chart_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _fileColor(String mime, bool isFolder) {
    if (isFolder) return AppTheme.blue;
    if (mime.startsWith('image/')) return AppTheme.green;
    if (mime.startsWith('audio/')) return AppTheme.pink;
    if (mime.startsWith('video/')) return AppTheme.purple;
    if (mime.contains('pdf')) return AppTheme.red;
    if (mime.contains('word')) return AppTheme.blue;
    if (mime.contains('excel')) return AppTheme.green;
    return AppTheme.orange;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _parentId != null
            ? AppBar(
                title: Text(_parentId == null ? '文件' : '浏览中...',
                    style: theme.textTheme.titleMedium),
              )
            : null,
        body: Column(
          children: [
            _buildHeader(theme),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const ShimmerList()
                  : _items.isEmpty
                      ? _buildEmpty(theme)
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _buildFileRow(_items[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
      child: Row(
        children: [
          if (_parentId != null) ...[
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 28),
              onPressed: _goBack,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              _parentId == null ? '文件' : '浏览中...',
              style: theme.textTheme.headlineLarge,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 34,
            child: FilledButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('上传', style: TextStyle(fontSize: 15)),
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
            child: const Icon(Icons.folder_open_rounded, size: 36, color: AppTheme.blue),
          ),
          const SizedBox(height: 20),
          Text('暂无文件', style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(120),
          )),
          const SizedBox(height: 6),
          Text('点击上传添加文件', style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(80),
          )),
        ],
      ),
    );
  }

  Widget _buildFileRow(Map<String, dynamic> item) {
    final isFolder = item['is_folder'] == true;
    final mime = item['mime_type'] ?? '';
    final iconColor = _fileColor(mime, isFolder);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (isFolder) {
              _navigateTo(item['id']);
            } else {
              _openPreview(item['id']);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: iconColor.withAlpha(20),
                  ),
                  child: Icon(_fileIcon(mime, isFolder), color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['name'] ?? '',
                        style: const TextStyle(fontSize: 17, height: 1.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isFolder ? '文件夹' : _formatSize(item['size_bytes'] ?? 0),
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _LevelBadge(
                  level: item['confidentiality_level'] ?? 0,
                  isAdmin: ref.watch(authProvider).user?.role == 'admin',
                  onChanged: (newLevel) => _changeLevel(item['id'], newLevel),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(item['created_at'] ?? ''),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(100),
                  ),
                ),
                if (!isFolder)
                  PopupMenuButton(
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'preview', child: Text('预览')),
                      PopupMenuItem(value: 'download', child: Text('下载')),
                      PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                    ],
                    onSelected: (v) {
                      final id = item['id'];
                      final name = item['name'] ?? '';
                      if (v == 'preview') _openPreview(id);
                      if (v == 'download') _downloadFile(id, name);
                      if (v == 'delete') _deleteFile(id, name);
                    },
                    icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
      if (diff.inDays < 1) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _changeLevel(String fileId, int newLevel) async {
    try {
      await _api.dio.patch('/files/$fileId/level', data: {'confidentiality_level': newLevel});
      _loadFiles();
    } catch (e) {
      appLog('[CHANGE_LEVEL] error: $e');
    }
  }
}

const _levelNames = {0: '公开', 1: '内部', 2: '机密', 3: '绝密'};
const _levelColors = {0: AppTheme.green, 1: AppTheme.blue, 2: Colors.orange, 3: AppTheme.red};

class _LevelBadge extends StatelessWidget {
  final int level;
  final bool isAdmin;
  final void Function(int) onChanged;

  const _LevelBadge({required this.level, required this.isAdmin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final name = _levelNames[level] ?? '公开';
    final color = _levelColors[level] ?? AppTheme.green;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(120), width: 0.5),
      ),
      child: Text(name, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );

    if (!isAdmin) return badge;

    return PopupMenuButton<int>(
      offset: const Offset(0, 24),
      itemBuilder: (_) => _levelNames.entries.map((e) => PopupMenuItem(
        value: e.key,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: _levelColors[e.key] ?? AppTheme.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(e.value, style: const TextStyle(fontSize: 13)),
          if (e.key == level) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check, size: 14, color: AppTheme.green),
          ],
        ]),
      )).toList(),
      onSelected: (v) => onChanged(v),
      child: badge,
    );
  }
}
