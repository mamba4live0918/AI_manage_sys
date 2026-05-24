import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' show Platform;
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';

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
    final result = await FilePicker.platform.pickFiles();
    if (result?.files.single.path != null) {
      final file = result!.files.single;
      final bytes = await file.readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
        if (_parentId != null) 'parent_id': _parentId,
      });
      try {
        await _api.dio.post('/files/upload', data: formData);
        _loadFiles();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
        }
      }
    }
  }

  Future<void> _deleteFile(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "$name" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
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

  IconData _fileIcon(String mime, bool isFolder) {
    if (isFolder) return Icons.folder;
    if (mime.startsWith('image/')) return Icons.image;
    if (mime.startsWith('audio/')) return Icons.audio_file;
    if (mime.startsWith('video/')) return Icons.videocam;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('word') || mime.contains('document')) return Icons.description;
    if (mime.contains('excel') || mime.contains('sheet')) return Icons.table_chart;
    return Icons.insert_drive_file;
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
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_parentId != null)
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack),
                Expanded(
                  child: Text(
                    _parentId == null ? '文件管理' : '浏览中...',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.upload),
                  label: const Text('上传'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // File list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text('暂无文件', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          final isFolder = item['is_folder'] == true;
                          final mime = item['mime_type'] ?? '';
                          return ListTile(
                            leading: Icon(_fileIcon(mime, isFolder), color: theme.colorScheme.primary),
                            title: Text(item['name'] ?? ''),
                            subtitle: isFolder ? Text('文件夹') : Text(_formatSize(item['size_bytes'] ?? 0)),
                            trailing: PopupMenuButton(
                              itemBuilder: (_) => [
                                if (!isFolder)
                                  const PopupMenuItem(value: 'preview', child: Text('预览')),
                                if (!isFolder)
                                  const PopupMenuItem(value: 'download', child: Text('下载')),
                                const PopupMenuItem(value: 'delete', child: Text('删除')),
                              ],
                              onSelected: (v) {
                                final id = item['id'];
                                final name = item['name'] ?? '';
                                if (v == 'preview') _openPreview(id);
                                if (v == 'delete') _deleteFile(id, name);
                              },
                            ),
                            onTap: () {
                              if (isFolder) {
                                _navigateTo(item['id']);
                              } else {
                                _openPreview(item['id']);
                              }
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
