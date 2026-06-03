import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../config/theme.dart';
import '../../services/knowledge_api.dart';
import '../marketing/marketing_knowledge_qa_page.dart';

class KnowledgeBasePage extends StatefulWidget {
  const KnowledgeBasePage({super.key});

  @override
  State<KnowledgeBasePage> createState() => _KnowledgeBasePageState();
}

class _KnowledgeBasePageState extends State<KnowledgeBasePage> {
  final _api = KnowledgeApi();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _departments = [];
  String? _currentDeptId;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _documents = [];
  String? _selectedCatId;
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _uploading = false;
  final Set<String> _expandedCats = {};

  // Drag state
  String? _draggingDocId;
  String? _dragOverCatId;

  @override
  void initState() {
    super.initState();
    _loadDepts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ──

  Future<void> _loadDepts() async {
    try {
      final depts = await _api.getDepartments();
      setState(() {
        _departments = depts;
        if (depts.isNotEmpty && _currentDeptId == null) _currentDeptId = depts.first['id'] as String;
      });
      if (_currentDeptId != null) _loadData();
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _loadData() async {
    if (_currentDeptId == null) return;
    setState(() => _loading = true);
    try {
      final cats = await _api.getCategories(_currentDeptId!);
      final docs = await _api.getDocuments(_currentDeptId!, categoryId: _selectedCatId, search: _searchCtrl.text, limit: 30, offset: (_page - 1) * 30);
      setState(() {
        _categories = cats; _documents = List<Map<String, dynamic>>.from(docs['items']); _total = docs['total'] as int? ?? 0; _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  void _switchDept(String deptId) {
    setState(() { _currentDeptId = deptId; _selectedCatId = null; _searchCtrl.clear(); _page = 1; _expandedCats.clear(); });
    _loadData();
  }

  void _selectCategory(String? catId) {
    setState(() { _selectedCatId = catId; _page = 1; });
    _loadData();
  }

  void _toggleExpand(String catId) {
    setState(() => _expandedCats.contains(catId) ? _expandedCats.remove(catId) : _expandedCats.add(catId));
  }

  // ── Drag & move ──

  Future<void> _moveDocToCategory(String docId, String docTitle, String catId, String catName) async {
    try {
      await _api.moveDocument(_currentDeptId!, docId, catId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$docTitle」→ $catName'), duration: const Duration(seconds: 1)));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移动失败: $e')));
    }
  }

  // ── Category CRUD ──

  Future<void> _createCategory({String? parentId}) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(parentId == null ? '新建分类' : '新建子分类'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '分类名称', isDense: true), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('创建'))],
    ));
    if (r == null || r.trim().isEmpty) return;
    try {
      await _api.createCategory(_currentDeptId!, name: r.trim(), parentId: parentId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分类已创建')));
      if (parentId != null) _expandedCats.add(parentId);
      _loadData();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败: $e'))); }
  }

  Future<void> _renameCategory(String catId, String cur) async {
    final ctrl = TextEditingController(text: cur);
    final r = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('重命名'), content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '新名称', isDense: true), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('确定'))],
    ));
    if (r == null || r.trim().isEmpty || r.trim() == cur) return;
    try { await _api.updateCategory(_currentDeptId!, catId, name: r.trim()); _loadData(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败: $e'))); }
  }

  Future<void> _deleteCategory(String catId, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除分类'), content: Text('确定要删除「$name」吗？子分类会提升到上级。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))],
    ));
    if (ok != true) return;
    try { await _api.deleteCategory(_currentDeptId!, catId); if (_selectedCatId == catId) _selectedCatId = null; _loadData(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'))); }
  }

  // ── Document actions ──

  Future<void> _upload() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true, withReadStream: false);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first; if (f.bytes == null) return;
    setState(() => _uploading = true);
    try { await _api.uploadDocument(_currentDeptId!, bytes: f.bytes!, fileName: f.name, categoryIds: _selectedCatId ?? ''); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传成功: ${f.name}'))); _loadData(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e'))); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  Future<void> _deleteDoc(String docId, String title) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('删除文档'), content: Text('确定要删除「$title」吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'))],
    ));
    if (ok != true) return;
    try { await _api.deleteDocument(_currentDeptId!, docId); _loadData(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e'))); }
  }

  Future<void> _toggleArchive(String docId, bool cur) async {
    try { await _api.archiveDocument(_currentDeptId!, docId, !cur); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(cur ? '已取消归档' : '已归档'))); _loadData(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e'))); }
  }

  Future<void> _downloadDoc(String docId, String title) async {
    try {
      final r = await _api.getDocumentFileUrl(_currentDeptId!, docId); final url = r['url'] as String?;
      if (url != null && mounted) { await Clipboard.setData(ClipboardData(text: url)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('「$title」下载链接已复制'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取失败: $e'))); }
  }

  void _previewDoc(Map<String, dynamic> d) {
    final content = d['content'] as String? ?? '';
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: Text(d['title'] as String? ?? ''), actions: [
        IconButton(icon: const Icon(Icons.copy_rounded), tooltip: '复制全文', onPressed: () { Clipboard.setData(ClipboardData(text: content)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); }),
      ]),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(content, style: const TextStyle(fontSize: 14, height: 1.8))),
    )));
  }

  void _qa() { if (_currentDeptId == null) return; MarketingKnowledgeQAPage.show(context, qaEndpoint: '/knowledge/$_currentDeptId/chat', historyEndpoint: '/knowledge/$_currentDeptId/chat/history', title: '知识库问答'); }

  // ── Tree helpers ──

  List<Map<String, dynamic>> _rootCats() => _categories.where((c) => c['parent_id'] == null).toList()..sort((a, b) => ((a['sort_order'] as int?) ?? 0).compareTo((b['sort_order'] as int?) ?? 0));
  List<Map<String, dynamic>> _childrenOf(String pid) => _categories.where((c) => c['parent_id'] == pid).toList()..sort((a, b) => ((a['sort_order'] as int?) ?? 0).compareTo((b['sort_order'] as int?) ?? 0));

  IconData _fileIcon(String ft) {
    switch (ft) { case 'pdf': return Icons.picture_as_pdf_rounded; case 'docx': case 'doc': return Icons.description_rounded; case 'xlsx': case 'xls': case 'csv': return Icons.table_chart_rounded; case 'pptx': case 'ppt': return Icons.slideshow_rounded; case 'txt': case 'md': return Icons.article_rounded; default: return Icons.insert_drive_file_rounded; }
  }
  Color _fileColor(String ft) {
    switch (ft) { case 'pdf': return Colors.red; case 'docx': case 'doc': return Colors.blue; case 'xlsx': case 'xls': return Colors.green; case 'pptx': case 'ppt': return Colors.orange; default: return AppTheme.purple; }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surf = isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid;
    final border = isDark ? AppTheme.darkBorder : Colors.grey.shade200;
    final dim = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Stack(children: [
      Column(children: [
        _deptTabs(isDark),
        _toolbar(isDark),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _categorySidebar(isDark, surf, border, dim),
                Expanded(child: _docList(isDark)),
              ])),
      ]),
      Positioned(right: 24, bottom: 24, child: FloatingActionButton.small(onPressed: _qa, tooltip: 'AI 知识问答', child: const Icon(Icons.chat_rounded))),
    ]);
  }

  Widget _deptTabs(bool isDark) {
    if (_departments.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity, decoration: BoxDecoration(color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid, border: Border(bottom: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.grey.shade200))),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (int i = 0; i < _departments.length; i++) ...[
          GestureDetector(onTap: () => _switchDept(_departments[i]['id'] as String), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _currentDeptId == _departments[i]['id'] ? AppTheme.blue : Colors.transparent, width: 2))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_currentDeptId == _departments[i]['id'] ? Icons.business_rounded : Icons.business_outlined, size: 18, color: _currentDeptId == _departments[i]['id'] ? AppTheme.blue : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
              const SizedBox(width: 6),
              Text(_departments[i]['name'] as String? ?? '', style: TextStyle(fontSize: 14, fontWeight: _currentDeptId == _departments[i]['id'] ? FontWeight.w600 : FontWeight.w400, color: _currentDeptId == _departments[i]['id'] ? AppTheme.blue : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
            ]),
          )),
          if (i < _departments.length - 1) const SizedBox(width: 4),
        ],
      ])),
    );
  }

  Widget _toolbar(bool isDark) {
    return Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Expanded(child: TextField(controller: _searchCtrl, decoration: InputDecoration(
        hintText: '搜索文档...', prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { _searchCtrl.clear(); setState(() => _page = 1); _loadData(); }) : null,
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.grey.shade300)),
        filled: true, fillColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
      ), onChanged: (v) { setState(() {}); _page = 1; _loadData(); })),
      const SizedBox(width: 10),
      Material(color: AppTheme.blue.withAlpha(isDark ? 25 : 18), borderRadius: BorderRadius.circular(12), child: InkWell(onTap: _uploading ? null : _upload, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_uploading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.blue)) else const Icon(Icons.upload_file_rounded, size: 18, color: AppTheme.blue),
          const SizedBox(width: 6), Text(_uploading ? '上传中...' : '上传文档', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.blue)),
        ])))),
    ]));
  }

  // ── Category sidebar (with drag targets) ──

  Widget _categorySidebar(bool isDark, Color surf, Color border, Color dim) {
    return Container(width: 240, decoration: BoxDecoration(color: surf, border: Border(right: BorderSide(color: border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
          Text('文件树', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dim)), const Spacer(),
          _tinyBtn(Icons.create_new_folder_rounded, '新建分类', () => _createCategory(), dim),
        ])),
        Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
          _buildDropTarget(null, '全部文档', Icons.inventory_2_rounded, docCount: _total),
          const SizedBox(height: 2),
          for (final cat in _rootCats()) _buildTree(cat, isDark, 0),
        ])),
      ]),
    );
  }

  Widget _buildTree(Map<String, dynamic> cat, bool isDark, int depth) {
    final catId = cat['id'] as String; final expanded = _expandedCats.contains(catId); final children = _childrenOf(catId);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildDropTarget(catId, cat['name'] as String? ?? '', expanded && children.isNotEmpty ? Icons.folder_open_rounded : Icons.folder_rounded,
          docCount: cat['document_count'] as int? ?? 0, indent: depth + 1, hasChildren: children.isNotEmpty, isExpanded: expanded,
          onExpand: () => _toggleExpand(catId), onRename: () => _renameCategory(catId, cat['name'] as String? ?? ''), onDelete: () => _deleteCategory(catId, cat['name'] as String? ?? ''), onAddSub: () => _createCategory(parentId: catId)),
      if (expanded && children.isNotEmpty) for (final c in children) _buildTree(c, isDark, depth + 1),
    ]);
  }

  Widget _buildDropTarget(String? catId, String name, IconData icon, {
    int docCount = 0, int indent = 0, bool hasChildren = false, bool isExpanded = false,
    VoidCallback? onExpand, VoidCallback? onRename, VoidCallback? onDelete, VoidCallback? onAddSub,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedCatId == catId;
    final isDragOver = _dragOverCatId == catId;
    final textColor = isSelected ? AppTheme.blue : (isDark ? AppTheme.darkText : AppTheme.lightText);

    Widget row = Padding(
      padding: EdgeInsets.only(left: 8.0 + indent * 16, right: 6, top: 6, bottom: 6),
      child: Row(children: [
        if (hasChildren)
          GestureDetector(onTap: onExpand, child: Icon(isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: textColor.withAlpha(160)))
        else
          const SizedBox(width: 16),
        const SizedBox(width: 2),
        Icon(isDragOver ? Icons.move_to_inbox_rounded : icon, size: 16, color: isDragOver ? AppTheme.blue : textColor.withAlpha(isSelected ? 255 : 180)),
        const SizedBox(width: 8),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: isSelected || isDragOver ? FontWeight.w600 : FontWeight.w400, color: isDragOver ? AppTheme.blue : textColor))),
        if (docCount > 0)
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: isDark ? AppTheme.darkBorder : Colors.grey.shade200),
            child: Text('$docCount', style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          ),
        if (catId != null) _hoverActions(isDark, onAddSub: onAddSub, onRename: onRename, onDelete: onDelete),
      ]),
    );

    Widget container = Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isDragOver ? AppTheme.blue.withAlpha(isDark ? 40 : 25) : (isSelected ? AppTheme.blue.withAlpha(isDark ? 20 : 15) : Colors.transparent),
        borderRadius: BorderRadius.circular(4),
        border: isDragOver ? Border.all(color: AppTheme.blue, width: 1.5) : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _selectCategory(catId),
          child: row,
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => catId != null && d.data != catId,
      onAcceptWithDetails: (d) {
        final docId = d.data;
        final doc = _documents.firstWhere((x) => x['id'] == docId, orElse: () => <String, dynamic>{});
        _moveDocToCategory(docId, doc['title'] as String? ?? '', catId!, name);
        setState(() => _dragOverCatId = null);
      },
      onLeave: (_) => setState(() => _dragOverCatId = null),
      builder: (ctx, candidateData, rejectedData) {
        if (candidateData.isNotEmpty && _dragOverCatId != catId) {
          WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _dragOverCatId = catId); });
        }
        return container;
      },
    );
  }

  Widget _hoverActions(bool isDark, {VoidCallback? onAddSub, VoidCallback? onRename, VoidCallback? onDelete}) {
    final c = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _tinyBtn(Icons.add_rounded, '子分类', onAddSub, c), const SizedBox(width: 2),
      _tinyBtn(Icons.edit_rounded, '重命名', onRename, c), const SizedBox(width: 2),
      _tinyBtn(Icons.delete_outline_rounded, '删除', onDelete, AppTheme.red),
    ]);
  }

  Widget _tinyBtn(IconData icon, String tooltip, VoidCallback? onTap, Color color) {
    return GestureDetector(onTap: onTap, child: Tooltip(message: tooltip, child: Container(width: 24, height: 24, decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)), child: Icon(icon, size: 14, color: color))));
  }

  // ── Document list (with draggable cards) ──

  Widget _docList(bool isDark) {
    if (_documents.isEmpty) {
      final c = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.menu_book_rounded, size: 48, color: c), const SizedBox(height: 8),
        Text(_searchCtrl.text.isNotEmpty ? '没有匹配的文档' : '拖拽文档到左侧分类即可归类，点击"上传文档"开始', style: TextStyle(color: c)),
      ]));
    }
    return LayoutBuilder(builder: (ctx, cts) {
      final cols = cts.maxWidth >= 600 ? 2 : 1;
      final cardW = (cts.maxWidth - 12 * (cols + 1)) / cols;
      return SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_total > 30) Padding(padding: const EdgeInsets.only(bottom: 8), child: _pager(isDark)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in _documents) SizedBox(width: cardW, child: _draggableDocCard(d, isDark)),
          ]),
          if (_total > 30) Padding(padding: const EdgeInsets.only(top: 8), child: _pager(isDark)),
        ]));
    });
  }

  Widget _draggableDocCard(Map<String, dynamic> d, bool isDark) {
    final docId = d['id'] as String;
    return LongPressDraggable<String>(
      data: docId,
      delay: const Duration(milliseconds: 300),
      feedback: Material(
        elevation: 6, borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: isDark ? AppTheme.darkSurfaceAlt : AppTheme.lightSurfaceSolid),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.drag_indicator_rounded, size: 18, color: AppTheme.blue),
            const SizedBox(width: 8),
            Flexible(child: Text(d['title'] as String? ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.blue), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _docCard(d, isDark)),
      onDragStarted: () => setState(() => _draggingDocId = docId),
      onDragEnd: (_) => setState(() { _draggingDocId = null; _dragOverCatId = null; }),
      child: _docCard(d, isDark),
    );
  }

  Widget _pager(bool isDark) {
    final tp = (_total / 30).ceil();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.chevron_left_rounded, size: 18), onPressed: _page > 1 ? () { setState(() => _page--); _loadData(); } : null),
      Text('$_page / $tp', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
      IconButton(icon: const Icon(Icons.chevron_right_rounded, size: 18), onPressed: _page < tp ? () { setState(() => _page++); _loadData(); } : null),
    ]);
  }

  Widget _docCard(Map<String, dynamic> d, bool isDark) {
    final title = d['title'] as String? ?? '';
    final preview = d['content_preview'] as String? ?? '';
    final ft = d['file_type'] as String? ?? '';
    final tags = (d['tags'] as List?)?.cast<String>() ?? <String>[];
    final docId = d['id'] as String;
    final archived = d['is_archived'] as bool? ?? false;
    final fColor = _fileColor(ft);
    final cats = (d['categories'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid, border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null, boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))]),
      child: Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: fColor)), const SizedBox(width: 10),
          Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: fColor.withAlpha(isDark ? 30 : 20)), child: Icon(_fileIcon(ft), color: fColor, size: 20)), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
              if (archived) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: Colors.orange.withAlpha(30)), child: const Text('已归档', style: TextStyle(fontSize: 10, color: Colors.orange)))],
            ]),
            const SizedBox(height: 2),
            Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          ])),
          // Drag handle hint
          Icon(Icons.drag_indicator_rounded, size: 16, color: (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary).withAlpha(80)),
        ]),
        if (tags.isNotEmpty || cats.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(left: 13), child: Wrap(spacing: 4, runSpacing: 4, children: [
            for (final c in cats) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppTheme.teal.withAlpha(isDark ? 25 : 18)), child: Text(c['name'] as String? ?? '', style: const TextStyle(fontSize: 10, color: AppTheme.teal))),
            for (final t in tags) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppTheme.blue.withAlpha(isDark ? 20 : 15)), child: Text(t, style: TextStyle(fontSize: 10, color: AppTheme.blue.withAlpha(isDark ? 220 : 240)))),
          ])),
        ],
        const SizedBox(height: 8),
        Padding(padding: const EdgeInsets.only(left: 13), child: Wrap(spacing: 6, runSpacing: 4, children: [
          _chip(Icons.visibility_rounded, '预览', fColor, () => _previewDoc(d), isDark),
          if (ft.isNotEmpty) _chip(Icons.download_rounded, '下载', fColor, () => _downloadDoc(docId, title), isDark),
          _chip(archived ? Icons.unarchive_rounded : Icons.archive_rounded, archived ? '取消归档' : '归档', Colors.orange, () => _toggleArchive(docId, archived), isDark),
          _chip(Icons.delete_outline_rounded, '删除', AppTheme.red, () => _deleteDoc(docId, title), isDark),
        ])),
      ])),
    );
  }

  Widget _chip(IconData icon, String label, Color color, VoidCallback onTap, bool isDark) {
    return Material(color: color.withAlpha(isDark ? 25 : 18), borderRadius: BorderRadius.circular(12), child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
        ]))));
  }
}
