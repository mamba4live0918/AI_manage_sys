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
  List<Map<String, dynamic>> _allItems = [];
  String? _currentFolderId;
  final _folderStack = <String?>[];
  bool _loading = true;
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _loadTree();
  }

  Future<void> _loadTree() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/files/tree');
      setState(() {
        _allItems = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _childrenOf(String? parentId) =>
      _allItems.where((i) => i['parent_id'] == parentId).toList()
        ..sort((a, b) {
          final aF = a['is_folder'] == true ? 0 : 1;
          final bF = b['is_folder'] == true ? 0 : 1;
          if (aF != bF) return aF.compareTo(bF);
          return (a['name'] as String? ?? '').toLowerCase().compareTo((b['name'] as String? ?? '').toLowerCase());
        });

  List<Map<String, dynamic>> get _currentItems => _childrenOf(_currentFolderId);

  void _navigateTo(String? folderId) {
    _folderStack.add(_currentFolderId);
    setState(() => _currentFolderId = folderId);
  }

  void _goBack() {
    if (_folderStack.isNotEmpty) {
      setState(() => _currentFolderId = _folderStack.removeLast());
    }
  }

  // ── CRUD ──

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result?.files.single.bytes == null) return;
    final file = result!.files.single;
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
      if (_currentFolderId != null) 'parent_id': _currentFolderId,
    });
    try {
      await _api.dio.post('/files/upload', data: formData);
      _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    }
  }

  Future<void> _createFolder({String? parentId}) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新建文件夹'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '文件夹名', isDense: true),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('创建')),
      ],
    ));
    if (r == null || r.trim().isEmpty) return;
    try {
      await _api.dio.post('/files/folder', data: {'name': r.trim(), 'parent_id': parentId ?? _currentFolderId});
      _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  Future<void> _rename(String id, String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('重命名'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '新名称', isDense: true),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定')),
      ],
    ));
    if (r == null || r.trim().isEmpty || r.trim() == currentName) return;
    try {
      await _api.dio.patch('/files/$id/rename', data: {'name': r.trim()});
      _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败: $e')));
    }
  }

  Future<void> _deleteItem(String id, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除'), content: Text('确定要删除 "$name" 吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
      ],
    ));
    if (ok != true) return;
    try {
      await _api.dio.delete('/files/$id');
      _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  void _openPreview(String fileId) => context.go('/files/preview/$fileId');

  Future<void> _downloadFile(String id, String name) async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择保存文件夹');
      if (dir == null) return;
      await _api.dio.download('/preview/download/$id', '$dir/$name');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已下载: $name')));
    } catch (e) {
      appLog('[DOWNLOAD] error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败: $e')));
    }
  }

  Future<void> _changeLevel(String fileId, int newLevel) async {
    try {
      await _api.dio.patch('/files/$fileId/level', data: {'confidentiality_level': newLevel});
      _loadTree();
    } catch (e) {
      appLog('[CHANGE_LEVEL] error: $e');
    }
  }

  // ── Icon helpers ──

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

  String _formatSize(int? bytes) {
    if (bytes == null || bytes < 1024) return '${bytes ?? 0} B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
      if (diff.inDays < 1) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) { return ''; }
  }

  // ── Tree helpers ──

  void _toggleFolder(String id) {
    setState(() => _expandedFolders.contains(id) ? _expandedFolders.remove(id) : _expandedFolders.add(id));
  }

  List<Map<String, dynamic>> _rootFolders() =>
      _allItems.where((i) => i['parent_id'] == null && i['is_folder'] == true).toList()
        ..sort((a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo((b['name'] as String? ?? '').toLowerCase()));

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surf = isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid;
    final border = isDark ? AppTheme.darkBorder : Colors.grey.shade200;

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _loading
            ? const ShimmerList()
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── File tree sidebar ──
                Container(
                  width: 240,
                  decoration: BoxDecoration(color: surf, border: Border(right: BorderSide(color: border))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(children: [
                        Text('文件树', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                        const Spacer(),
                        _tinyBtn(Icons.create_new_folder_rounded, '新建文件夹', () => _createFolder(), isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                      ]),
                    ),
                    Expanded(
                      child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
                        _treeItem(null, '根目录', Icons.folder_open_rounded, isRoot: true),
                        const SizedBox(height: 2),
                        for (final f in _rootFolders()) _buildTreeNode(f, isDark, 0),
                      ]),
                    ),
                  ]),
                ),
                // ── File list ──
                Expanded(child: _buildFilePanel(isDark)),
              ]),
      ),
    );
  }

  // ── Tree node ──

  Widget _buildTreeNode(Map<String, dynamic> item, bool isDark, int depth) {
    final id = item['id'] as String;
    final hasChildren = _allItems.any((i) => i['parent_id'] == id && i['is_folder'] == true);
    final isExpanded = _expandedFolders.contains(id);
    final children = _allItems.where((i) => i['parent_id'] == id && i['is_folder'] == true).toList()
      ..sort((a, b) => (a['name'] as String? ?? '').toLowerCase().compareTo((b['name'] as String? ?? '').toLowerCase()));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _treeItem(id, item['name'] as String? ?? '', hasChildren && isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
          indent: depth + 1, hasChildren: hasChildren, isExpanded: isExpanded,
          onExpand: () => _toggleFolder(id),
          onRename: () => _rename(id, item['name'] as String? ?? ''),
          onDelete: () => _deleteItem(id, item['name'] as String? ?? ''),
          onAddSub: () => _createFolder(parentId: id)),
      if (isExpanded && children.isNotEmpty)
        for (final ch in children) _buildTreeNode(ch, isDark, depth + 1),
    ]);
  }

  Widget _treeItem(String? id, String name, IconData icon, {
    bool isRoot = false, int indent = 0, bool hasChildren = false, bool isExpanded = false,
    VoidCallback? onExpand, VoidCallback? onRename, VoidCallback? onDelete, VoidCallback? onAddSub,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _currentFolderId == id;
    final textColor = isSelected ? AppTheme.blue : (isDark ? AppTheme.darkText : AppTheme.lightText);

    return MouseRegion(
      child: Material(
        color: isSelected ? AppTheme.blue.withAlpha(isDark ? 20 : 15) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            if (id != null) _navigateTo(id);
            if (isRoot) _navigateTo(null);
          },
          child: Padding(
            padding: EdgeInsets.only(left: 8.0 + indent * 16, right: 6, top: 6, bottom: 6),
            child: Row(children: [
              if (hasChildren)
                GestureDetector(onTap: onExpand, child: Icon(isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: textColor.withAlpha(160)))
              else
                const SizedBox(width: 16),
              const SizedBox(width: 2),
              Icon(icon, size: 16, color: isSelected ? AppTheme.blue : isDark ? AppTheme.teal : AppTheme.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: textColor))),
              if (!isRoot) _hoverBtns(isDark, onAddSub: onAddSub, onRename: onRename, onDelete: onDelete),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _hoverBtns(bool isDark, {VoidCallback? onAddSub, VoidCallback? onRename, VoidCallback? onDelete}) {
    final c = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _tinyBtn(Icons.create_new_folder_rounded, '新建子文件夹', onAddSub, c),
      const SizedBox(width: 2),
      _tinyBtn(Icons.edit_rounded, '重命名', onRename, c),
      const SizedBox(width: 2),
      _tinyBtn(Icons.delete_outline_rounded, '删除', onDelete, AppTheme.red),
    ]);
  }

  Widget _tinyBtn(IconData icon, String tooltip, VoidCallback? onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(message: tooltip, child: Container(
        width: 24, height: 24,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
        child: Icon(icon, size: 14, color: color),
      )),
    );
  }

  // ── File panel ──

  Widget _buildFilePanel(bool isDark) {
    return Column(children: [
      // Breadcrumb + actions
      _buildHeader(isDark),
      const SizedBox(height: 8),
      Expanded(
        child: _currentItems.isEmpty
            ? _buildEmpty(isDark)
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _currentItems.length,
                itemBuilder: (_, i) => _buildFileRow(_currentItems[i]),
              ),
      ),
    ]);
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(children: [
        if (_folderStack.isNotEmpty || _currentFolderId != null) ...[
          IconButton(icon: const Icon(Icons.chevron_left_rounded, size: 28), onPressed: _goBack, padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40)),
          const SizedBox(width: 4),
        ],
        Expanded(child: Text(_currentFolderId == null ? '文件' : '浏览中...', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
        const Spacer(),
        SizedBox(
          height: 34,
          child: FilledButton.icon(onPressed: _pickFile, icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('上传', style: TextStyle(fontSize: 15)),
              style: FilledButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
        ),
      ]),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: AppTheme.blue.withAlpha(15)),
          child: const Icon(Icons.folder_open_rounded, size: 36, color: AppTheme.blue)),
      const SizedBox(height: 20),
      Text('暂无文件', style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
      const SizedBox(height: 6),
      Text('点击上传添加文件', style: TextStyle(fontSize: 13, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
    ]));
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
          onTap: () => isFolder ? _navigateTo(item['id']) : _openPreview(item['id']),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                  color: iconColor.withAlpha(isFolder ? 25 : 18)),
                  child: Icon(_fileIcon(mime, isFolder), color: iconColor, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item['name'] ?? '', style: const TextStyle(fontSize: 17, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(isFolder ? '文件夹' : _formatSize(item['size_bytes']), style: TextStyle(fontSize: 14, color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
              ])),
              const SizedBox(width: 8),
              _LevelBadge(level: item['confidentiality_level'] ?? 0, isAdmin: ref.watch(authProvider).user?.role == 'admin',
                  onChanged: (nl) => _changeLevel(item['id'], nl)),
              const SizedBox(width: 8),
              Text(_formatDate(item['created_at'] ?? ''), style: TextStyle(fontSize: 13, color: (Theme.of(context).brightness == Brightness.dark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
              PopupMenuButton(
                itemBuilder: (_) => [
                  if (isFolder) const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  if (isFolder) const PopupMenuItem(value: 'delete_folder', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                  if (!isFolder) const PopupMenuItem(value: 'preview', child: Text('预览')),
                  if (!isFolder) const PopupMenuItem(value: 'download', child: Text('下载')),
                  if (!isFolder) const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                ],
                onSelected: (v) {
                  final id = item['id']; final name = item['name'] ?? '';
                  if (v == 'preview') _openPreview(id);
                  if (v == 'download') _downloadFile(id, name);
                  if (v == 'delete' || v == 'delete_folder') _deleteItem(id, name);
                  if (v == 'rename') _rename(id, name);
                },
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
              ),
            ]),
          ),
        ),
      ),
    );
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
      decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withAlpha(120), width: 0.5)),
      child: Text(name, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
    if (!isAdmin) return badge;
    return PopupMenuButton<int>(
      offset: const Offset(0, 24),
      itemBuilder: (_) => _levelNames.entries.map((e) => PopupMenuItem(value: e.key,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _levelColors[e.key] ?? AppTheme.green, shape: BoxShape.circle)),
          const SizedBox(width: 8), Text(e.value, style: const TextStyle(fontSize: 13)),
          if (e.key == level) ...[const SizedBox(width: 6), const Icon(Icons.check, size: 14, color: AppTheme.green)],
        ]))).toList(),
      onSelected: (v) => onChanged(v),
      child: badge,
    );
  }
}
