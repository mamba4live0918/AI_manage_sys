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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                    style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
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
    final isDark = theme.brightness == Brightness.dark;

  Widget _buildCoursewareCard(Map<String, dynamic> c, bool isDark) {
    final id = c['id'] as String;
    final title = c['title'] as String? ?? '';
    final type = c['type'] as String? ?? '';
    final fileId = c['file_id'] as String?;
    final content = c['content'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppTheme.red)),
            const SizedBox(width: 8),
            Text('课件文档', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            const Spacer(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onSelected: (action) {
                if (action == 'delete') _delete(id, title);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'delete',
                    child: Text('删除', style: TextStyle(color: AppTheme.red))),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: AppTheme.red.withAlpha(isDark ? 25 : 18)),
              child: Icon(
                fileId != null ? Icons.picture_as_pdf_rounded : Icons.menu_book_rounded,
                color: AppTheme.red, size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(child: Text('$type · v${c['version']}', style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (fileId != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: fileId!))),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.visibility_rounded, size: 14, color: AppTheme.blue),
                    ),
                  ),
                ],
              ]),
            ])),
          ]),
        ]),
      ),
    );
  }

    return Column(children: [
      LayoutBuilder(
        builder: (ctx, constraints) {
          final btnWide = constraints.maxWidth >= 500;
          return Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 40,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _upload,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(btnWide ? '上传课件 (PDF/PPT/DOC)' : '上传课件'),
              ),
            ),
          );
        },
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? Center(child: Text('暂无课件',
                    style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w >= 500 ? 2 : 1;
                      final cardWidth = (w - 12 * (cols + 1)) / cols;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final c in _items)
                            SizedBox(
                              width: cardWidth,
                              child: _buildCoursewareCard(c, isDark),
                            ),
                        ]),
                      );
                    },
                  ),
      ),
    ]);
  }
}
