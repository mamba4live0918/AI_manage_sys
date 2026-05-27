import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../preview/preview_page.dart';
import 'marketing_knowledge_qa_page.dart';

class MarketingKnowledgeManagePage extends StatefulWidget {
  const MarketingKnowledgeManagePage({super.key});

  @override
  State<MarketingKnowledgeManagePage> createState() => _MarketingKnowledgeManagePageState();
}

class _MarketingKnowledgeManagePageState extends State<MarketingKnowledgeManagePage> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/marketing/knowledge', queryParameters: {'limit': 100});
      setState(() {
        _entries = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(f.bytes!, filename: f.name),
      });
      final resp = await _api.dio.post('/marketing/knowledge/upload', data: formData);
      if (mounted && resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传成功: ${f.name}')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    } finally {
      setState(() => _uploading = false);
    }
  }

  void _previewFile(String sourceFileId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: sourceFileId)));
  }

  Future<void> _downloadFile(String entryId, String fileName) async {
    try {
      final resp = await _api.dio.get('/marketing/knowledge/$entryId/file-url');
      final url = resp.data['url'] as String?;
      if (url != null && mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件「$fileName」的下载链接已复制到剪贴板，请在浏览器中打开')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取下载链接失败: $e')));
      }
    }
  }

  Future<void> _deleteEntry(String entryId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除知识条目'),
        content: Text('确定要删除「$title」吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.dio.delete('/marketing/knowledge/$entryId');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('条目已删除')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  void _qa() {
    MarketingKnowledgeQAPage.show(context,
      historyEndpoint: '/marketing/knowledge/qa-history',
    );
  }

  IconData _fileIcon(String? fileName) {
    if (fileName == null) return Icons.menu_book_rounded;
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (ext.endsWith('.docx') || ext.endsWith('.doc')) return Icons.description_rounded;
    if (ext.endsWith('.xlsx') || ext.endsWith('.xls')) return Icons.table_chart_rounded;
    if (ext.endsWith('.pptx') || ext.endsWith('.ppt')) return Icons.slideshow_rounded;
    if (ext.endsWith('.txt') || ext.endsWith('.md')) return Icons.article_rounded;
    if (ext.endsWith('.csv') || ext.endsWith('.json')) return Icons.data_object_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _fileIconColor(String? fileName) {
    if (fileName == null) return AppTheme.purple;
    final ext = fileName.toLowerCase();
    if (ext.endsWith('.pdf')) return Colors.red;
    if (ext.endsWith('.docx') || ext.endsWith('.doc')) return Colors.blue;
    if (ext.endsWith('.xlsx') || ext.endsWith('.xls')) return Colors.green;
    if (ext.endsWith('.pptx') || ext.endsWith('.ppt')) return Colors.orange;
    return AppTheme.purple;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: _qa,
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('AI 知识问答', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(_uploading ? '上传中...' : '上传文件', style: const TextStyle(fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.purple,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.upload_file_rounded, size: 48, color: theme.colorScheme.onSurface.withAlpha(60)),
                      const SizedBox(height: 8),
                      Text('暂无知识条目，点击"上传文件"添加', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))),
                    ]),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      final sourceFileId = e['source_file_id'] as String?;
                      final title = e['title'] as String? ?? '';
                      final entryId = e['id'] as String;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 2),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(children: [
                            CircleAvatar(
                              backgroundColor: _fileIconColor(title).withAlpha(25),
                              radius: 16,
                              child: Icon(_fileIcon(title), color: _fileIconColor(title), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                Row(children: [
                                  Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                  if ((e['category'] as String? ?? '').isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: AppTheme.purple.withAlpha(15)),
                                      child: Text(e['category'] as String? ?? '', style: const TextStyle(fontSize: 10, color: AppTheme.purple)),
                                    ),
                                  ],
                                ]),
                                const SizedBox(height: 2),
                                Text(e['content_preview'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(120))),
                              ]),
                            ),
                            if (sourceFileId != null) ...[
                              IconButton(
                                icon: const Icon(Icons.visibility_rounded, size: 18),
                                tooltip: '预览',
                                onPressed: () => _previewFile(sourceFileId),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                icon: const Icon(Icons.download_rounded, size: 18),
                                tooltip: '下载',
                                onPressed: () => _downloadFile(entryId, title),
                                visualDensity: VisualDensity.compact,
                              ),
                              ],
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              tooltip: '删除条目',
                              onPressed: () => _deleteEntry(entryId, title),
                              visualDensity: VisualDensity.compact,
                              color: Colors.red.withAlpha(150),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
