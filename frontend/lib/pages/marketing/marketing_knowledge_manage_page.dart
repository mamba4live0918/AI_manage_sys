import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../services/knowledge_api.dart';
import '../preview/preview_page.dart';
import 'marketing_knowledge_qa_page.dart';

class MarketingKnowledgeManagePage extends StatefulWidget {
  const MarketingKnowledgeManagePage({super.key});

  @override
  State<MarketingKnowledgeManagePage> createState() => _MarketingKnowledgeManagePageState();
}

class _MarketingKnowledgeManagePageState extends State<MarketingKnowledgeManagePage> {
  final _api = ApiClient();
  final _kbApi = KnowledgeApi();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _categories = [];
  String? _deptId;
  String? _selectedCatId;
  int _page = 1;
  bool _loading = true;
  bool _uploading = false;
  final Set<String> _expandedCats = {};

  // 未分类的 fake id
  static const _uncategorizedId = '__uncategorized__';

  @override
  void initState() {
    super.initState();
    _initDept();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDept() async {
    try {
      final depts = await _kbApi.getDepartments();
      final mkt = depts.cast<Map<String, dynamic>?>().firstWhere(
        (d) => (d!['name'] as String? ?? '').contains('市场'),
        orElse: () => depts.isNotEmpty ? depts.first : null,
      );
      if (mkt != null) {
        setState(() => _deptId = mkt['id'] as String);
        _loadData();
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadData() async {
    if (_deptId == null) return;
    setState(() => _loading = true);
    try {
      final cats = await _kbApi.getCategories(_deptId!);
      final resp = await _api.dio.get('/marketing/knowledge', queryParameters: {
        'search': _searchCtrl.text,
        'limit': 100,
        'offset': (_page - 1) * 100,
      });
      final entries = List<Map<String, dynamic>>.from(resp.data['items']);

      // 从 knowledge_entries 的 category 字段中提取分类名，同步到 kb_categories
      final existingNames = cats.map((c) => c['name'] as String).toSet();
      for (final e in entries) {
        final catName = (e['category'] as String? ?? '').trim();
        if (catName.isNotEmpty && !existingNames.contains(catName)) {
          // 自动创建缺失的分类
          try {
            final newCat = await _kbApi.createCategory(_deptId!, name: catName);
            cats.add(newCat);
            existingNames.add(catName);
          } catch (_) {}
        }
      }

      setState(() {
        _categories = cats;
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _selectCategory(String? catId) {
    setState(() { _selectedCatId = catId; _page = 1; });
    // 选了分类就按分类名过滤
    _loadData();
  }

  String? _categoryNameForId(String? catId) {
    if (catId == null) return null;
    for (final c in _categories) {
      if (c['id'] == catId) return c['name'];
    }
    return null;
  }

  void _toggleExpand(String catId) {
    setState(() => _expandedCats.contains(catId) ? _expandedCats.remove(catId) : _expandedCats.add(catId));
  }

  // ── 获取/创建"未分类" ──

  String? get _uncategorizedCatId {
    for (final c in _categories) {
      if (c['name'] == '未分类' && c['parent_id'] == null) return c['id'] as String;
    }
    return null;
  }

  // ── Category CRUD ──

  Future<void> _createCategory({String? parentId}) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(parentId == null ? '新建分类' : '新建子分类'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '分类名称', isDense: true),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('创建')),
      ],
    ));
    if (r == null || r.trim().isEmpty) return;
    try {
      await _kbApi.createCategory(_deptId!, name: r.trim(), parentId: parentId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分类已创建')));
      if (parentId != null) _expandedCats.add(parentId);
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  Future<void> _renameCategory(String catId, String cur) async {
    final ctrl = TextEditingController(text: cur);
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('重命名'), content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '新名称', isDense: true), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定'))],
    ));
    if (r == null || r.trim().isEmpty || r.trim() == cur) return;
    try { await _kbApi.updateCategory(_deptId!, catId, name: r.trim()); _loadData(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败: $e'))); }
  }

  Future<void> _deleteCategory(String catId, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除分类'), content: Text('确定要删除「$name」吗？子分类会提升到上级。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))],
    ));
    if (ok != true) return;
    try { await _kbApi.deleteCategory(_deptId!, catId); if (_selectedCatId == catId) _selectedCatId = null; _loadData(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'))); }
  }

  // ── 移动子目录到其他父目录 ──

  Future<void> _moveCategoryToParent(String catId, String catName) async {
    final parentOptions = <Map<String, dynamic>>[
      {'id': null, 'name': '根目录（顶级）'},
      for (final c in _categories) if (c['id'] != catId) c,
    ];
    final current = _categories.firstWhere((c) => c['id'] == catId, orElse: () => <String, dynamic>{});
    String? selectedParentId = current.isNotEmpty ? current['parent_id'] as String? : null;

    final r = await showDialog<String?>(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) => AlertDialog(
      title: const Text('移动分类'), content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('将「$catName」移到：', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          ...parentOptions.map((p) => RadioListTile<String?>(
            title: Text(p['name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
            value: p['id'] as String?,
            groupValue: selectedParentId,
            dense: true, contentPadding: EdgeInsets.zero,
            onChanged: (v) => setDlg(() => selectedParentId = v),
          )),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, selectedParentId), child: const Text('移动')),
      ],
    )));
    if (r == null || r == current['parent_id']) return;
    try {
      await _kbApi.moveCategory(_deptId!, catId, targetParentId: r);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移动')));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移动失败: $e')));
    }
  }

  // ── 上传（选目录） ──

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true, withReadStream: false);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;

    // 弹出选目录对话框
    String? chosenCatId = _selectedCatId;
    final catOptions = <Map<String, dynamic>>[
      {'id': _uncategorizedId, 'name': '未分类（默认）'},
      for (final c in _categories) c,
    ];

    final chosen = await showDialog<String?>(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) {
      return AlertDialog(
        title: Text('上传: ${f.name}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('选择目标目录：', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          ...catOptions.map((c) => RadioListTile<String>(
            title: Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
            value: c['id'] as String,
            groupValue: chosenCatId ?? _uncategorizedId,
            dense: true, contentPadding: EdgeInsets.zero,
            onChanged: (v) => setDlg(() => chosenCatId = v),
          )),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, chosenCatId ?? _uncategorizedId), child: const Text('上传')),
        ],
      );
    }));
    if (chosen == null) return;

    // 解析实际分类 ID（后端保证未分类始终存在，直接取）
    final actualCatId = chosen == _uncategorizedId ? _uncategorizedCatId! : chosen;

    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({'file': MultipartFile.fromBytes(f.bytes!, filename: f.name)});
      await _api.dio.post('/marketing/knowledge/upload', data: formData, queryParameters: {'category': actualCatId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传成功: ${f.name}')));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── 文档改目录 ──

  Future<void> _changeDocCategory(String entryId, String title) async {
    final catOptions = <Map<String, dynamic>>[
      {'id': _uncategorizedId, 'name': '未分类'},
      for (final c in _categories) c,
    ];
    String? chosenCatId;

    final chosen = await showDialog<String?>(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) => AlertDialog(
      title: Text('移动: $title'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('选择目标目录：', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        ...catOptions.map((c) => RadioListTile<String>(
          title: Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
          value: c['id'] as String,
          groupValue: chosenCatId,
          dense: true, contentPadding: EdgeInsets.zero,
          onChanged: (v) => setDlg(() => chosenCatId = v),
        )),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, chosenCatId), child: const Text('移动')),
      ],
    )));
    if (chosen == null) return;

    final actualCatId = chosen == _uncategorizedId ? _uncategorizedCatId! : chosen;

    try {
      // 更新 marketing knowledge entry 的 category
      await _api.dio.put('/marketing/knowledge/$entryId', data: {'category': actualCatId});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移动')));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移动失败: $e')));
    }
  }

  // ── 文档删除/下载/预览 ──

  Future<void> _deleteEntry(String entryId, String title) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除文档'), content: Text('确定要删除「$title」吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))],
    ));
    if (ok != true) return;
    try { await _api.dio.delete('/marketing/knowledge/$entryId'); _loadData(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'))); }
  }

  Future<void> _downloadFile(String entryId, String name) async {
    try {
      final resp = await _api.dio.get('/marketing/knowledge/$entryId/file-url');
      final url = resp.data['url'] as String?;
      if (url != null && mounted) {
        await Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$name」下载链接已复制')));
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e'))); }
  }

  void _qa() { MarketingKnowledgeQAPage.show(context, historyEndpoint: '/marketing/knowledge/qa-history'); }
  void _previewFile(String sourceFileId) { Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewPage(fileId: sourceFileId))); }

  // ── Tree helpers ──

  List<Map<String, dynamic>> _rootCats() => _categories.where((c) => c['parent_id'] == null).toList()..sort((a, b) => ((a['sort_order'] as int?) ?? 0).compareTo((b['sort_order'] as int?) ?? 0));
  List<Map<String, dynamic>> _childrenOf(String pid) => _categories.where((c) => c['parent_id'] == pid).toList()..sort((a, b) => ((a['sort_order'] as int?) ?? 0).compareTo((b['sort_order'] as int?) ?? 0));

  IconData _fileIcon(String? fn) {
    if (fn == null) return Icons.menu_book_rounded;
    final ext = fn.toLowerCase();
    if (ext.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (ext.endsWith('.docx') || ext.endsWith('.doc')) return Icons.description_rounded;
    if (ext.endsWith('.xlsx') || ext.endsWith('.xls')) return Icons.table_chart_rounded;
    if (ext.endsWith('.pptx') || ext.endsWith('.ppt')) return Icons.slideshow_rounded;
    if (ext.endsWith('.txt') || ext.endsWith('.md')) return Icons.article_rounded;
    return Icons.insert_drive_file_rounded;
  }
  Color _fileColor(String? fn) {
    if (fn == null) return AppTheme.purple;
    final ext = fn.toLowerCase();
    if (ext.endsWith('.pdf')) return Colors.red; if (ext.endsWith('.docx') || ext.endsWith('.doc')) return Colors.blue;
    if (ext.endsWith('.xlsx') || ext.endsWith('.xls')) return Colors.green; if (ext.endsWith('.pptx') || ext.endsWith('.ppt')) return Colors.orange;
    return AppTheme.purple;
  }

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
            _tinyBtn(Icons.create_new_folder_rounded, '新建分类', () => _createCategory(), dim),
          ])),
          Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
            _treeItem(null, '全部文档', Icons.inventory_2_rounded),
            const SizedBox(height: 2),
            for (final cat in _rootCats()) _buildTree(cat, isDark, 0),
          ])),
        ])),
      Expanded(child: Column(children: [
        _toolbar(isDark),
        Expanded(child: _entries.isEmpty ? _empty(isDark) : _docGrid(isDark)),
      ])),
    ]);
  }

  Widget _buildTree(Map<String, dynamic> cat, bool isDark, int depth) {
    final catId = cat['id'] as String;
    final isUncategorized = cat['name'] == '未分类' && cat['parent_id'] == null;
    final expanded = _expandedCats.contains(catId); final children = _childrenOf(catId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _treeItem(catId, cat['name'] as String? ?? '', expanded && children.isNotEmpty ? Icons.folder_open_rounded : Icons.folder_rounded,
          indent: depth + 1, hasChildren: children.isNotEmpty, isExpanded: expanded,
          onExpand: () => _toggleExpand(catId),
          onRename: isUncategorized ? null : () => _renameCategory(catId, cat['name'] as String? ?? ''),
          onDelete: isUncategorized ? null : () => _deleteCategory(catId, cat['name'] as String? ?? ''),
          onAddSub: isUncategorized ? null : () => _createCategory(parentId: catId),
          onMove: isUncategorized ? null : () => _moveCategoryToParent(catId, cat['name'] as String? ?? '')),
      if (expanded && children.isNotEmpty) for (final c in children) _buildTree(c, isDark, depth + 1),
    ]);
  }

  Widget _treeItem(String? catId, String name, IconData icon, {
    int indent = 0, bool hasChildren = false, bool isExpanded = false,
    VoidCallback? onExpand, VoidCallback? onRename, VoidCallback? onDelete, VoidCallback? onAddSub, VoidCallback? onMove,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedCatId == catId;
    final textColor = isSelected ? AppTheme.blue : (isDark ? AppTheme.darkText : AppTheme.lightText);
    return MouseRegion(
      child: Material(color: isSelected ? AppTheme.blue.withAlpha(isDark ? 20 : 15) : Colors.transparent, borderRadius: BorderRadius.circular(4),
        child: InkWell(borderRadius: BorderRadius.circular(4), onTap: () => _selectCategory(catId),
          child: Padding(padding: EdgeInsets.only(left: 8.0 + indent * 16, right: 6, top: 6, bottom: 6),
            child: Row(children: [
              if (hasChildren) GestureDetector(onTap: onExpand, child: Icon(isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: textColor.withAlpha(160)))
              else const SizedBox(width: 16),
              const SizedBox(width: 2), Icon(icon, size: 16, color: textColor.withAlpha(isSelected ? 255 : 180)), const SizedBox(width: 8),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: textColor))),
              if (catId != null) _hoverBtns(isDark, onAddSub: onAddSub, onRename: onRename, onDelete: onDelete, onMove: onMove),
            ])),
        )),
    );
  }

  Widget _hoverBtns(bool isDark, {VoidCallback? onAddSub, VoidCallback? onRename, VoidCallback? onDelete, VoidCallback? onMove}) {
    final c = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (onAddSub != null) _tinyBtn(Icons.add_rounded, '子分类', onAddSub, c),
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
        suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { _searchCtrl.clear(); setState(() {}); _loadData(); }) : null,
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.grey.shade300)),
        filled: true, fillColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
      ), onChanged: (v) { setState(() {}); _page = 1; _loadData(); })),
      const SizedBox(width: 8),
      Material(color: AppTheme.purple.withAlpha(isDark ? 25 : 18), borderRadius: BorderRadius.circular(12),
        child: InkWell(borderRadius: BorderRadius.circular(12), onTap: _qa, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.chat_rounded, size: 18, color: AppTheme.purple), SizedBox(width: 6), Text('AI 问答', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.purple))])))),
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
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.menu_book_rounded, size: 48, color: c), const SizedBox(height: 8), Text('暂无知识条目，点击"上传文档"添加', style: TextStyle(color: c))]));
  }

  Widget _docGrid(bool isDark) {
    return LayoutBuilder(builder: (ctx, cts) {
      final cols = cts.maxWidth >= 500 ? 2 : 1;
      final cardW = (cts.maxWidth - 12 * (cols + 1)) / cols;
      return SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _entries) SizedBox(width: cardW, child: _docCard(e, isDark)),
      ]));
    });
  }

  Widget _docCard(Map<String, dynamic> e, bool isDark) {
    final title = e['title'] as String? ?? '';
    final entryId = e['id'] as String;
    final sourceFileId = e['source_file_id'] as String?;
    final fColor = _fileColor(title);
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid, border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null, boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))]),
      child: Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: fColor)), const SizedBox(width: 10),
          Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: fColor.withAlpha(isDark ? 30 : 20)), child: Icon(_fileIcon(title), color: fColor, size: 20)), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? AppTheme.darkText : AppTheme.lightText)))]),
            const SizedBox(height: 2),
            Text(e['content_preview'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          ])),
        ]),
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(left: 13), child: Wrap(spacing: 6, runSpacing: 4, children: [
          if (sourceFileId != null) _chip(Icons.visibility_rounded, '预览', AppTheme.purple, isDark, () => _previewFile(sourceFileId)),
          if (sourceFileId != null) _chip(Icons.download_rounded, '下载', AppTheme.purple, isDark, () => _downloadFile(entryId, title)),
          _chip(Icons.drive_file_move_rounded, '移目录', AppTheme.teal, isDark, () => _changeDocCategory(entryId, title)),
          _chip(Icons.delete_outline_rounded, '删除', AppTheme.red, isDark, () => _deleteEntry(entryId, title)),
        ])),
      ])),
    );
  }

  Widget _chip(IconData icon, String label, Color color, bool isDark, VoidCallback onTap) {
    return Material(color: color.withAlpha(isDark ? 25 : 18), borderRadius: BorderRadius.circular(12), child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color))]))));
  }
}
