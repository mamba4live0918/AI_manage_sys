import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../marketing/marketing_knowledge_qa_page.dart';
import '../preview/preview_page.dart';

class BiddingKnowledgeTab extends StatefulWidget {
  const BiddingKnowledgeTab({super.key});

  @override
  State<BiddingKnowledgeTab> createState() => _BiddingKnowledgeTabState();
}

class _BiddingKnowledgeTabState extends State<BiddingKnowledgeTab> {
  final _api = ApiClient();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _dirs = [];
  String? _selectedDirId;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dirsResp = await _api.dio.get('/bidding/knowledge/dirs');
      final params = <String, dynamic>{'limit': 100};
      if (_selectedDirId != null) params['dir_id'] = _selectedDirId;
      if (_searchCtrl.text.isNotEmpty) params['search'] = _searchCtrl.text;
      final docsResp = await _api.dio.get('/bidding/knowledge/docs', queryParameters: params);
      setState(() {
        _dirs = List<Map<String, dynamic>>.from(dirsResp.data['items']);
        _docs = List<Map<String, dynamic>>.from(docsResp.data['items']);
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
        'dir_id': _selectedDirId ?? '',
      });
      final resp = await _api.dio.post('/bidding/knowledge/docs/upload', data: formData);
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

  void _openQA() {
    MarketingKnowledgeQAPage.show(context,
      qaEndpoint: '/bidding/knowledge/qa',
      title: '招投标知识库问答',
      historyEndpoint: '/bidding/knowledge/qa-history',
    );
  }

  Future<void> _downloadFile(String docId, String fileName) async {
    try {
      final resp = await _api.dio.get('/bidding/knowledge/docs/$docId/file-url');
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

  Future<void> _deleteDoc(String docId, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文档'),
        content: Text('确定要删除「$title」吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.dio.delete('/bidding/knowledge/docs/$docId');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文档已删除')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  Future<void> _createDir() async {
    final nameCtrl = TextEditingController();
    String? parentId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建目录'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '目录名称 *')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '父目录'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: parentId,
                    isExpanded: true, isDense: true,
                    hint: const Text('根目录'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('根目录')),
                      ..._dirs.map((d) => DropdownMenuItem(
                        value: d['id'] as String?,
                        child: Text(d['name'] as String? ?? ''),
                      )),
                    ],
                    onChanged: (v) => setDlg(() => parentId = v),
                  ),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    await _api.dio.post('/bidding/knowledge/dirs', data: {
      'name': nameCtrl.text.trim(),
      'parent_id': parentId,
    });
    _load();
  }

  IconData _fileIcon(String? fileName) {
    if (fileName == null) return Icons.article_rounded;
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
    if (ext.endsWith('.pdf')) return AppTheme.red;
    if (ext.endsWith('.docx') || ext.endsWith('.doc')) return AppTheme.blue;
    if (ext.endsWith('.xlsx') || ext.endsWith('.xls')) return AppTheme.green;
    if (ext.endsWith('.pptx') || ext.endsWith('.ppt')) return AppTheme.orange;
    return AppTheme.purple;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索文档...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear_rounded, size: 16), onPressed: () { _searchCtrl.clear(); _load(); })
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  filled: true, fillColor: Colors.grey.withAlpha(15),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final buttons = <Widget>[
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _openQA,
                  icon: const Icon(Icons.chat_rounded, size: 16),
                  label: const Text('AI 问答', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                ),
              ),
              const SizedBox(width: 6, height: 6),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : _pickAndUpload,
                  icon: _uploading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_file_rounded, size: 16),
                  label: Text(_uploading ? '上传中...' : '上传文件', style: const TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6, height: 6),
              SizedBox(
                height: 36,
                child: OutlinedButton.icon(
                  onPressed: _createDir,
                  icon: const Icon(Icons.create_new_folder_rounded, size: 14),
                  label: const Text('目录', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ),
            ];
            if (constraints.maxWidth >= 600) {
              return Row(children: buttons);
            } else {
              return Wrap(children: buttons);
            }
          },
        ),
      ),
      if (_dirs.isNotEmpty)
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('全部', style: TextStyle(fontSize: 12)),
                  selected: _selectedDirId == null,
                  onSelected: (_) { _selectedDirId = null; _load(); },
                  visualDensity: VisualDensity.compact,
                ),
              ),
              ...(_dirs.map((d) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(d['name'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                  selected: _selectedDirId == d['id'],
                  onSelected: (_) { _selectedDirId = d['id'] as String?; _load(); },
                  visualDensity: VisualDensity.compact,
                ),
              ))),
            ],
          ),
        ),
      const SizedBox(height: 4),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _docs.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.upload_file_rounded, size: 48, color: theme.colorScheme.onSurface.withAlpha(60)),
                      const SizedBox(height: 8),
                      Text('暂无文档，点击"上传文件"添加', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))),
                    ]),
                  )
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w >= 500 ? 2 : 1;
                      final cardWidth = (w - 12 * (cols + 1)) / cols;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final d in _docs)
                            SizedBox(
                              width: cardWidth,
                              child: _buildDocCard(d, isDark),
                            ),
                        ]),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _buildDocCard(Map<String, dynamic> d, bool isDark) {
    final tags = (d['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? <String>[];
    final title = d['title'] as String? ?? '';
    final docId = d['id'] as String;
    final fileColor = _fileIconColor(title);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetail(docId, title),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: fileColor)),
                const SizedBox(width: 10),
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: fileColor.withAlpha(isDark ? 30 : 20),
                  ),
                  child: Icon(_fileIcon(title), color: fileColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                    const SizedBox(height: 2),
                    Text(d['content_preview'] as String? ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(d['updated_at']?.toString().substring(0, 10) ?? '',
                    style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
              ]),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: Wrap(spacing: 4, children: tags.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                    ),
                    child: Text(t, style: const TextStyle(fontSize: 10, color: AppTheme.purple)),
                  )).toList()),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  void _showDetail(String docId, String title) async {
    try {
      final resp = await _api.dio.get('/bidding/knowledge/docs/$docId');
      final full = resp.data;
      if (mounted) {
        final hasFile = full['file_id'] != null;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(title, overflow: TextOverflow.ellipsis),
              actions: [
                if (hasFile) ...[
                  IconButton(
                    icon: const Icon(Icons.visibility_rounded, size: 20),
                    tooltip: '预览文件',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: full['file_id']))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 20),
                    tooltip: '下载源文件',
                    onPressed: () => _downloadFile(docId, title),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: '删除文档',
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteDoc(docId, title);
                  },
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(full['content'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.8)),
            ),
          ),
        ));
      }
    } catch (_) {}
  }
}
