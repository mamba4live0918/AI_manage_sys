import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../preview/preview_page.dart';

class PmCoursewareTab extends StatefulWidget {
  const PmCoursewareTab({super.key});

  @override
  State<PmCoursewareTab> createState() => _PmCoursewareTabState();
}

class _PmCoursewareTabState extends State<PmCoursewareTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/pm/coursewares', queryParameters: {'limit': 50});
      setState(() {
        _items = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final titleCtrl = TextEditingController();
    String type = 'document';

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'ppt', 'pptx', 'doc', 'docx', 'md', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;

    titleCtrl.text = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('上传课件'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.insert_drive_file_rounded, size: 20, color: AppTheme.red),
                const SizedBox(width: 8),
                Expanded(child: Text(picked.name, overflow: TextOverflow.ellipsis)),
                Text('${(picked.size / 1024).toStringAsFixed(0)} KB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '课件标题')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '类型'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: type, isExpanded: true, isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'document', child: Text('文档')),
                      DropdownMenuItem(value: 'slides', child: Text('幻灯片')),
                      DropdownMenuItem(value: 'video', child: Text('视频')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) => setDlg(() => type = v!),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('上传')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(picked.bytes!, filename: picked.name),
        'title': titleCtrl.text.trim(),
        'type': type,
      });
      await _api.dio.post('/pm/coursewares/upload', data: formData);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('课件上传成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    }
  }

  Future<void> _delete(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除课件'),
        content: Text('确定要删除"$title"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/pm/coursewares/$id');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(height: 40, child: ElevatedButton.icon(
          onPressed: _upload,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('上传课件 (PDF/PPT/DOC)'),
        )),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(child: Text('暂无课件',
                    style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final c = _items[i];
                      final id = c['id'] as String;
                      final title = c['title'] as String? ?? '';
                      final type = c['type'] as String? ?? '';
                      final fileId = c['file_id'] as String?;
                      final content = c['content'] as String? ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: fileId != null ? const Color(0xFFFFEBEE) : const Color(0xFFFCE4EC),
                            child: Icon(
                              fileId != null ? Icons.picture_as_pdf_rounded : Icons.menu_book_rounded,
                              color: AppTheme.red, size: 20,
                            ),
                          ),
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('$type · v${c['version']}', maxLines: 1),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (fileId != null)
                              IconButton(
                                icon: const Icon(Icons.visibility_rounded, size: 18, color: AppTheme.blue),
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => PreviewPage(fileId: fileId),
                                  ));
                                },
                                tooltip: '预览课件',
                              ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18),
                              onSelected: (action) {
                                if (action == 'delete') _delete(id, title);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'delete',
                                    child: Text('删除', style: TextStyle(color: AppTheme.red))),
                              ],
                            ),
                          ]),
                          onTap: () {
                            if (fileId != null) {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PreviewPage(fileId: fileId),
                              ));
                            } else if (content.isNotEmpty) {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(title),
                                  content: SizedBox(
                                    width: double.maxFinite,
                                    height: 400,
                                    child: SingleChildScrollView(
                                      child: SelectableText(content),
                                    ),
                                  ),
                                  actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
