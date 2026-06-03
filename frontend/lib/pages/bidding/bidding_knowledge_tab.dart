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
  final Set<String> _expandedDirs = {};

  static const _uncategorizedId = '__uncategorized__';

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
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _selectDir(String? dirId) {
    setState(() { _selectedDirId = dirId; });
    _load();
  }

  void _toggleDir(String dirId) {
    setState(() => _expandedDirs.contains(dirId) ? _expandedDirs.remove(dirId) : _expandedDirs.add(dirId));
  }

  // ── 未分类 ──

  String? get _uncategorizedDirId {
    for (final d in _dirs) {
      if (d['name'] == '未分类' && d['parent_id'] == null) return d['id'] as String;
    }
    return null;
  }

  // ── Dir CRUD ──

  Future<void> _createDir({String? parentId}) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(parentId == null ? '新建目录' : '新建子目录'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '目录名称', isDense: true), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('创建'))],
    ));
    if (r == null || r.trim().isEmpty) return;
    await _api.dio.post('/bidding/knowledge/dirs', data: {'name': r.trim(), 'parent_id': parentId});
    if (parentId != null) _expandedDirs.add(parentId);
    _load();
  }

  Future<void> _renameDir(String dirId, String cur) async {
    final ctrl = TextEditingController(text: cur);
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('重命名'), content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '新名称', isDense: true), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定'))],
    ));
    if (r == null || r.trim().isEmpty || r.trim() == cur) return;
    await _api.dio.put('/bidding/knowledge/dirs/$dirId', data: {'name': r.trim()});
    _load();
  }

  Future<void> _deleteDir(String dirId, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除目录'), content: Text('确定要删除「$name」吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))],
    ));
    if (ok != true) return;
    await _api.dio.delete('/bidding/knowledge/dirs/$dirId');
    if (_selectedDirId == dirId) _selectedDirId = null;
    _load();
  }

  Future<void> _moveDirToParent(String dirId, String name) async {
    final options = <Map<String, dynamic>>[
      {'id': null, 'name': '根目录（顶级）'},
      for (final d in _dirs) if (d['id'] != dirId) d,
    ];
    final cur = _dirs.firstWhere((d) => d['id'] == dirId, orElse: () => <String, dynamic>{});
    String? selected = cur.isNotEmpty ? cur['parent_id'] as String? : null;

    final r = await showDialog<String?>(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) => AlertDialog(
      title: const Text('移动目录'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('将「$name」移到：', style: const TextStyle(fontSize: 13)), const SizedBox(height: 8),
        ...options.map((o) => RadioListTile<String?>(title: Text(o['name'] as String? ?? '', style: const TextStyle(fontSize: 13)), value: o['id'] as String?, groupValue: selected, dense: true, contentPadding: EdgeInsets.zero, onChanged: (v) => setDlg(() => selected = v))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('移动'))],
    )));
    if (r == null || r == cur['parent_id']) return;
    await _api.dio.put('/bidding/knowledge/dirs/$dirId', data: {'name': name, 'parent_id': r});
    _load();
  }

  // ── 上传（选目录） ──

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true, withReadStream: false);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;

    String? chosenDirId = _selectedDirId;
    final options = <Map<String, dynamic>>[
      {'id': _uncategorizedId, 'name': '未分类（默认）'},
      for (final d in _dirs) d,
    ];

    final chosen = await showDialog<String?>(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) {
      return AlertDialog(
        title: Text('上传: ${f.name}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('选择目标目录：', style: TextStyle(fontSize: 13)), const SizedBox(height: 8),
          ...options.map((o) => RadioListTile<String>(title: Text(o['name'] as String? ?? '', style: const TextStyle(fontSize: 13)), value: o['id'] as String, groupValue: chosenDirId ?? _uncategorizedId, dense: true, contentPadding: EdgeInsets.zero, onChanged: (v) => setDlg(() => chosenDirId = v))),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, chosenDirId ?? _uncategorizedId), child: const Text('上传'))],
      );
    }));
    if (chosen == null) return;

    final actualDirId = chosen == _uncategorizedId ? _uncategorizedDirId! : chosen;

    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({'file': MultipartFile.fromBytes(f.bytes!, filename: f.name), 'dir_id': actualDirId});
      await _api.dio.post('/bidding/knowledge/docs/upload', data: formData);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传成功: ${f.name}')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── 文档改目录 ──

  Future<void> _changeDocDir(String docId, String title) async {
    final options = <Map<String, dynamic>>[
      {'id': _uncategorizedId, 'name': '未分类'},
      for (final d in _dirs) d,
    ];
    String? chosen;

    final r = await showDialog<String?>(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) => AlertDialog(
      title: Text('移动: $title'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('选择目标目录：', style: TextStyle(fontSize: 13)), const SizedBox(height: 8),
        ...options.map((o) => RadioListTile<String>(title: Text(o['name'] as String? ?? '', style: const TextStyle(fontSize: 13)), value: o['id'] as String, groupValue: chosen, dense: true, contentPadding: EdgeInsets.zero, onChanged: (v) => setDlg(() => chosen = v))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, chosen), child: const Text('移动'))],
    )));
    if (r == null) return;

    final actualId = r == _uncategorizedId ? _uncategorizedDirId! : r;
    await _api.dio.put('/bidding/knowledge/docs/$docId', data: {'dir_id': actualId});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移动')));
    _load();
  }

  void _openQA() {
    MarketingKnowledgeQAPage.show(context, qaEndpoint: '/bidding/knowledge/qa', title: '招投标知识库问答', historyEndpoint: '/bidding/knowledge/qa-history');
  }

  Future<void> _downloadFile(String docId, String name) async {
    try {
      final resp = await _api.dio.get('/bidding/knowledge/docs/$docId/file-url');
      final url = resp.data['url'] as String?;
      if (url != null && mounted) { await Clipboard.setData(ClipboardData(text: url)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$name」下载链接已复制'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e'))); }
  }

  Future<void> _deleteDoc(String docId, String title) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除文档'), content: Text('确定要删除「$title」吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))],
    ));
    if (ok != true) return;
    await _api.dio.delete('/bidding/knowledge/docs/$docId');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文档已删除')));
    _load();
  }

  void _showDetail(String docId, String title) async {
    try {
      final resp = await _api.dio.get('/bidding/knowledge/docs/$docId');
      final full = resp.data;
      final hasFile = full['file_id'] != null;
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis), actions: [
            if (hasFile) ...[
              IconButton(icon: const Icon(Icons.visibility_rounded, size: 20), tooltip: '预览', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: full['file_id'])))),
              IconButton(icon: const Icon(Icons.download_rounded, size: 20), tooltip: '下载', onPressed: () => _downloadFile(docId, title)),
            ],
            IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 20), tooltip: '删除', onPressed: () { Navigator.pop(context); _deleteDoc(docId, title); }),
          ]),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(full['content'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.8))),
        )));
      }
    } catch (_) {}
  }

  // ── File type ──

  IconData _fileIcon(String? fn) {
    if (fn == null) return Icons.article_rounded;
    switch (fn.toLowerCase().split('.').last) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'docx': case 'doc': return Icons.description_rounded;
      case 'xlsx': case 'xls': return Icons.table_chart_rounded;
      case 'pptx': case 'ppt': return Icons.slideshow_rounded;
      case 'txt': case 'md': return Icons.article_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }
  Color _fileColor(String? fn) {
    if (fn == null) return AppTheme.purple;
    switch (fn.toLowerCase().split('.').last) {
      case 'pdf': return AppTheme.red; case 'docx': case 'doc': return AppTheme.blue;
      case 'xlsx': case 'xls': return AppTheme.green; case 'pptx': case 'ppt': return AppTheme.orange;
      default: return AppTheme.purple;
    }
  }

  // ── Tree ──

  List<Map<String, dynamic>> _rootDirs() => _dirs.where((d) => d['parent_id'] == null).toList();
  List<Map<String, dynamic>> _childrenDirs(String pid) => _dirs.where((d) => d['parent_id'] == pid).toList();

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surf = isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid;
    final border = isDark ? AppTheme.darkBorder : Colors.grey.shade200;
    final dim = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    if (_loading) return const Center(child: CircularProgressIndicator());

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 220, decoration: BoxDecoration(color: surf, border: Border(right: BorderSide(color: border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
            Text('文件树', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dim)), const Spacer(),
            _tinyBtn(Icons.create_new_folder_rounded, '新建目录', () => _createDir(), dim),
          ])),
          Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
            _treeItem(null, '全部文档', Icons.inventory_2_rounded),
            const SizedBox(height: 2),
            for (final d in _rootDirs()) _buildTree(d, isDark, 0),
          ])),
        ])),
      Expanded(child: Column(children: [
        _toolbar(isDark),
        Expanded(child: _docs.isEmpty ? _empty(isDark) : _docGrid(isDark)),
      ])),
    ]);
  }

  Widget _buildTree(Map<String, dynamic> dir, bool isDark, int depth) {
    final dirId = dir['id'] as String;
    final isUncategorized = dir['name'] == '未分类' && dir['parent_id'] == null;
    final expanded = _expandedDirs.contains(dirId); final children = _childrenDirs(dirId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _treeItem(dirId, dir['name'] as String? ?? '', expanded && children.isNotEmpty ? Icons.folder_open_rounded : Icons.folder_rounded,
          indent: depth + 1, hasChildren: children.isNotEmpty, isExpanded: expanded,
          onExpand: () => _toggleDir(dirId),
          onRename: isUncategorized ? null : () => _renameDir(dirId, dir['name'] as String? ?? ''),
          onDelete: isUncategorized ? null : () => _deleteDir(dirId, dir['name'] as String? ?? ''),
          onAddSub: isUncategorized ? null : () => _createDir(parentId: dirId),
          onMove: isUncategorized ? null : () => _moveDirToParent(dirId, dir['name'] as String? ?? '')),
      if (expanded && children.isNotEmpty) for (final c in children) _buildTree(c, isDark, depth + 1),
    ]);
  }

  Widget _treeItem(String? dirId, String name, IconData icon, {
    int indent = 0, bool hasChildren = false, bool isExpanded = false,
    VoidCallback? onExpand, VoidCallback? onRename, VoidCallback? onDelete, VoidCallback? onAddSub, VoidCallback? onMove,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedDirId == dirId;
    final textColor = isSelected ? AppTheme.blue : (isDark ? AppTheme.darkText : AppTheme.lightText);
    return MouseRegion(child: Material(color: isSelected ? AppTheme.blue.withAlpha(isDark ? 20 : 15) : Colors.transparent, borderRadius: BorderRadius.circular(4),
      child: InkWell(borderRadius: BorderRadius.circular(4), onTap: () => _selectDir(dirId),
        child: Padding(padding: EdgeInsets.only(left: 8.0 + indent * 16, right: 6, top: 6, bottom: 6), child: Row(children: [
          if (hasChildren) GestureDetector(onTap: onExpand, child: Icon(isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: textColor.withAlpha(160)))
          else const SizedBox(width: 16),
          const SizedBox(width: 2), Icon(icon, size: 16, color: textColor.withAlpha(isSelected ? 255 : 180)), const SizedBox(width: 8),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: textColor))),
          if (dirId != null) _hoverBtns(isDark, onAddSub: onAddSub, onRename: onRename, onDelete: onDelete, onMove: onMove),
        ]))),
    ));
  }

  Widget _hoverBtns(bool isDark, {VoidCallback? onAddSub, VoidCallback? onRename, VoidCallback? onDelete, VoidCallback? onMove}) {
    final c = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (onAddSub != null) _tinyBtn(Icons.add_rounded, '子目录', onAddSub, c),
      if (onAddSub != null) const SizedBox(width: 2),
      if (onRename != null) _tinyBtn(Icons.edit_rounded, '重命名', onRename, c),
      if (onRename != null) const SizedBox(width: 2),
      if (onMove != null) _tinyBtn(Icons.drive_file_move_rounded, '移到...', onMove, c),
      if (onMove != null) const SizedBox(width: 2),
      if (onDelete != null) _tinyBtn(Icons.delete_outline_rounded, '删除', onDelete, AppTheme.red),
    ]);
  }

  Widget _tinyBtn(IconData icon, String tooltip, VoidCallback? onTap, Color color) {
    return GestureDetector(onTap: onTap, child: Tooltip(message: tooltip, child: Container(width: 24, height: 24, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)), child: Icon(icon, size: 14, color: color))));
  }

  Widget _toolbar(bool isDark) {
    return Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Expanded(child: TextField(controller: _searchCtrl, decoration: InputDecoration(
        hintText: '搜索文档...', prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { _searchCtrl.clear(); _load(); }) : null,
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.grey.shade300)),
        filled: true, fillColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
      ), onSubmitted: (_) => _load())),
      const SizedBox(width: 8),
      Material(color: AppTheme.purple.withAlpha(isDark ? 25 : 18), borderRadius: BorderRadius.circular(12),
        child: InkWell(borderRadius: BorderRadius.circular(12), onTap: _openQA, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.chat_rounded, size: 18, color: AppTheme.purple), SizedBox(width: 6), Text('AI 问答', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.purple))])))),
      const SizedBox(width: 8),
      Material(color: AppTheme.blue.withAlpha(isDark ? 25 : 18), borderRadius: BorderRadius.circular(12),
        child: InkWell(borderRadius: BorderRadius.circular(12), onTap: _uploading ? null : _pickAndUpload, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_uploading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.blue))
          else const Icon(Icons.upload_file_rounded, size: 18, color: AppTheme.blue),
          const SizedBox(width: 6), Text(_uploading ? '上传中...' : '上传文档', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.blue)),
        ])))),
    ]));
  }

  Widget _empty(bool isDark) {
    final c = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.upload_file_rounded, size: 48, color: c), const SizedBox(height: 8), Text('暂无文档，点击"上传文档"添加', style: TextStyle(color: c))]));
  }

  Widget _docGrid(bool isDark) {
    return LayoutBuilder(builder: (ctx, cts) {
      final cols = cts.maxWidth >= 500 ? 2 : 1;
      final cardW = (cts.maxWidth - 12 * (cols + 1)) / cols;
      return SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in _docs) SizedBox(width: cardW, child: _docCard(d, isDark)),
      ]));
    });
  }

  Widget _docCard(Map<String, dynamic> d, bool isDark) {
    final tags = (d['tags'] as List<dynamic>?)?.map((t) => t.toString()).toList() ?? <String>[];
    final title = d['title'] as String? ?? '';
    final docId = d['id'] as String;
    final fColor = _fileColor(title);
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid, border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null, boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))]),
      child: Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => _showDetail(docId, title),
        child: Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: fColor)), const SizedBox(width: 10),
            Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: fColor.withAlpha(isDark ? 30 : 20)), child: Icon(_fileIcon(title), color: fColor, size: 20)), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? AppTheme.darkText : AppTheme.lightText)),
              const SizedBox(height: 2),
              Text(d['content_preview'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            ])),
            const SizedBox(width: 8),
            Text(d['updated_at']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          ]),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(padding: const EdgeInsets.only(left: 13), child: Wrap(spacing: 4, children: tags.map((t) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppTheme.purple.withAlpha(isDark ? 25 : 18)), child: Text(t, style: const TextStyle(fontSize: 10, color: AppTheme.purple)))).toList())),
          ],
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.only(left: 13), child: Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(Icons.visibility_rounded, '详情', AppTheme.purple, isDark, () => _showDetail(docId, title)),
            _chip(Icons.drive_file_move_rounded, '移目录', AppTheme.teal, isDark, () => _changeDocDir(docId, title)),
            _chip(Icons.delete_outline_rounded, '删除', AppTheme.red, isDark, () => _deleteDoc(docId, title)),
          ])),
        ])),
      )),
    );
  }

  Widget _chip(IconData icon, String label, Color color, bool isDark, VoidCallback onTap) {
    return Material(color: color.withAlpha(isDark ? 25 : 18), borderRadius: BorderRadius.circular(12), child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color))]))));
  }
}
