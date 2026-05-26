import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import '../../widgets/shimmer.dart';
import '../../widgets/html_frame.dart';
import '../../utils/app_logger.dart';

const _platformNames = {
  'wechat': '公众号',
  'moments': '朋友圈',
  'xiaohongshu': '小红书',
  'douyin': '抖音',
  'other': '其他',
};

const _toneOptions = ['专业严谨', '轻松活泼', '温情故事', '悬念吸引', '促销紧迫', '幽默风趣'];
const _purposeOptions = ['品牌宣传', '产品推广', '活动营销', '知识科普', '故事传播'];

class IpDashboardPage extends ConsumerStatefulWidget {
  const IpDashboardPage({super.key});

  @override
  ConsumerState<IpDashboardPage> createState() => _IpDashboardPageState();
}

class _IpDashboardPageState extends ConsumerState<IpDashboardPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  late final TabController _tabCtrl;

  // template list
  List<Map<String, dynamic>> _templates = [];
  bool _loadingTemplates = true;
  String? _templatesError;

  // generate form
  final _topicCtrl = TextEditingController();
  final _coreInfoCtrl = TextEditingController();
  final _audienceCtrl = TextEditingController();
  String _platform = 'wechat';
  String _tone = '专业严谨';
  String _purpose = '品牌宣传';

  bool _generating = false;

  // history
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_tabCtrl.indexIsChanging && _tabCtrl.index == 2) _loadHistory();
      });
    _loadTemplates();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appLog('[IP] First frame rendered, mounted=$mounted, tabIndex=${_tabCtrl.index}');
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _topicCtrl.dispose();
    _coreInfoCtrl.dispose();
    _audienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() { _loadingTemplates = true; _templatesError = null; });
    try {
      final resp = await _api.dio.get('/copy/templates');
      final items = List<Map<String, dynamic>>.from(resp.data['items']);
      appLog('[TEMPLATES] loaded ${items.length} templates');
      setState(() { _templates = items; _loadingTemplates = false; });
    } catch (e) {
      appLog('[TEMPLATES] load error: $e');
      setState(() { _templatesError = '$e'; _loadingTemplates = false; });
    }
  }

  Future<void> _generate() async {
    if (_topicCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写产品/主题')),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final resp = await _api.dio.post('/copy/generate-direct', data: {
        'platform_type': _platform,
        'topic': _topicCtrl.text.trim(),
        'core_info': _coreInfoCtrl.text.trim(),
        'target_audience': _audienceCtrl.text.trim(),
        'tone': _tone,
        'purpose': _purpose,
      });
      final content = resp.data['content'] as String? ?? '';
      final html = resp.data['content_html'] as String? ?? '';
      final model = resp.data['model'] as String? ?? '';
      _loadHistory();
      if (mounted) _showPreviewDialog(_topicCtrl.text.trim(), content, html, model);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e')),
        );
      }
    }
    setState(() => _generating = false);
  }

  Future<void> _saveTemplate() async {
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    String platform = 'wechat';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建模板'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '模板名称')),
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: const InputDecoration(labelText: '平台'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: platform,
                      isExpanded: true, isDense: true,
                      items: _platformNames.entries.map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setDlg(() => platform = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: contentCtrl, maxLines: 5,
                  decoration: const InputDecoration(labelText: '模板内容', hintText: '用 {变量名} 表示占位符')),
                const SizedBox(height: 10),
                TextField(controller: promptCtrl, maxLines: 3,
                  decoration: const InputDecoration(labelText: '系统提示词（可选）')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _api.dio.post('/copy/templates', data: {
      'name': nameCtrl.text.trim(),
      'platform_type': platform,
      'template_content': contentCtrl.text.trim(),
      'system_prompt': promptCtrl.text.trim(),
    });
    _loadTemplates();
  }

  Future<void> _deleteTemplate(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: const Text('确定要删除这个模板吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _api.dio.delete('/copy/templates/$id');
    _loadTemplates();
  }

  Future<void> _editTemplate(Map<String, dynamic> t) async {
    final nameCtrl = TextEditingController(text: t['name'] ?? '');
    final contentCtrl = TextEditingController(text: t['template_content'] ?? '');
    final promptCtrl = TextEditingController(text: t['system_prompt'] ?? '');
    String platform = t['platform_type'] as String? ?? 'wechat';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('编辑模板'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '模板名称')),
                const SizedBox(height: 10),
                InputDecorator(
                  decoration: const InputDecoration(labelText: '平台'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: platform,
                      isExpanded: true, isDense: true,
                      items: _platformNames.entries.map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setDlg(() => platform = v!),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: contentCtrl, maxLines: 5,
                  decoration: const InputDecoration(labelText: '模板内容', hintText: '用 {变量名} 表示占位符')),
                const SizedBox(height: 10),
                TextField(controller: promptCtrl, maxLines: 3,
                  decoration: const InputDecoration(labelText: '系统提示词（可选）')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _api.dio.put('/copy/templates/${t['id']}', data: {
      'name': nameCtrl.text.trim(),
      'platform_type': platform,
      'template_content': contentCtrl.text.trim(),
      'system_prompt': promptCtrl.text.trim(),
    });
    _loadTemplates();
  }

  void _showPreviewDialog(String title, String content, String html, String model) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _CopyPreviewPage(title: title, content: content, html: html, model: model),
    ));
  }

  Future<void> _loadHistory() async {
    setState(() { _loadingHistory = true; _historyError = null; });
    try {
      final resp = await _api.dio.get('/copy/history');
      setState(() { _history = List<Map<String, dynamic>>.from(resp.data['items']); _loadingHistory = false; });
    } catch (e) {
      appLog('[HISTORY] load error: $e');
      setState(() { _historyError = '$e'; _loadingHistory = false; });
    }
  }

  Future<void> _viewHistoryDetail(Map<String, dynamic> record) async {
    try {
      final resp = await _api.dio.get('/copy/history/${record['id']}');
      final detail = resp.data;
      final topic = detail['topic'] as String? ?? '历史记录';
      final content = detail['content'] as String? ?? '';
      final html = detail['content_html'] as String? ?? '';
      final model = detail['model'] as String? ?? '';
      if (mounted) _showPreviewDialog(topic, content, html, model);
    } catch (_) {}
  }

  Future<void> _deleteHistory(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除记录'),
        content: const Text('确定要删除这条生成记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.dio.delete('/copy/history/$id');
      _loadHistory();
    } catch (_) {}
  }

  Future<void> _editHistory(Map<String, dynamic> record) async {
    final id = record['id'] as String;
    final topicCtrl = TextEditingController(text: record['topic'] as String? ?? '');
    final contentCtrl = TextEditingController();
    String? content;

    // load full content
    try {
      final resp = await _api.dio.get('/copy/history/$id');
      content = resp.data['content'] as String? ?? '';
      contentCtrl.text = content;
    } catch (_) {
      return;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑记录'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: topicCtrl, decoration: const InputDecoration(labelText: '主题')),
                const SizedBox(height: 12),
                TextField(controller: contentCtrl, maxLines: 15,
                  decoration: const InputDecoration(labelText: '内容', alignLabelWithHint: true)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            await _api.dio.put('/copy/history/$id', data: {
              'topic': topicCtrl.text.trim(),
              'content': contentCtrl.text,
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _loadHistory();
          }, child: const Text('保存')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('讲师IP'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '模板管理'),
            Tab(text: '文案生成'),
            Tab(text: '历史记录'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildTemplatesTab(theme, isDark),
          _buildGenerateTab(theme, isDark),
          _buildHistoryTab(theme, isDark),
        ],
      ),
    ),
    );
  }

  Widget _buildTemplatesTab(ThemeData theme, bool isDark) {
    appLog('[BUILD] _buildTemplatesTab called, loading=$_loadingTemplates error=$_templatesError items=${_templates.length}');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(
          children: [
            Text('${_templates.length} 个模板',
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withAlpha(120))),
            const Spacer(),
            SizedBox(
              height: 36,
              child: ElevatedButton.icon(
                onPressed: _saveTemplate,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新建', style: TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: _loadingTemplates
                ? const Center(child: CircularProgressIndicator())
                : _templatesError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 40, color: Colors.red),
                            const SizedBox(height: 12),
                            Text('加载失败: ${_templatesError}',
                              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(onPressed: _loadTemplates, child: const Text('重试')),
                          ],
                        ),
                      )
                    : _templates.isEmpty
                        ? Center(
                            child: Text('暂无模板，点击"新建"创建',
                              style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _templates.length,
                            itemBuilder: (_, i) {
                              final t = _templates[i];
                              final platform = t['platform_type'] as String? ?? 'wechat';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      _topicCtrl.text = t['name'] as String? ?? '';
                                      _platform = platform;
                                      _tabCtrl.animateTo(1);
                                      setState(() {});
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36, height: 36,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(9),
                                              color: AppTheme.purple.withAlpha(20),
                                            ),
                                            child: const Icon(Icons.article_rounded, color: AppTheme.purple, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(t['name'] ?? '', style: const TextStyle(fontSize: 17)),
                                                const SizedBox(height: 2),
                                                Text(_platformNames[platform] ?? platform,
                                                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(100))),
                                              ],
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _editTemplate(t),
                                            child: Container(
                                              width: 32, height: 32,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                color: AppTheme.purple.withAlpha(15),
                                              ),
                                              child: const Icon(Icons.edit_rounded, size: 17, color: AppTheme.purple),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          GestureDetector(
                                            onTap: () => _deleteTemplate(t['id']),
                                            child: Container(
                                              width: 32, height: 32,
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                color: AppTheme.red.withAlpha(15),
                                              ),
                                              child: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.red),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
        ),
      ]);
  }

  Widget _buildGenerateTab(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // platform
          _buildFieldLabel('平台'),
          const SizedBox(height: 4),
          InputDecorator(
            decoration: _inputDeco(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _platform,
                isExpanded: true, isDense: true,
                items: _platformNames.entries.map((e) =>
                  DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: (v) => setState(() => _platform = v!),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // topic
          _buildFieldLabel('产品/主题 *'),
          const SizedBox(height: 4),
          TextField(
            controller: _topicCtrl,
            decoration: _inputDeco(hint: '例如：智能手表'),
          ),
          const SizedBox(height: 14),

          // core info
          _buildFieldLabel('核心信息'),
          const SizedBox(height: 4),
          TextField(
            controller: _coreInfoCtrl,
            maxLines: 5,
            decoration: _inputDeco(hint: '输入产品的核心卖点、特点、规格等信息...'),
          ),
          const SizedBox(height: 14),

          // target audience
          _buildFieldLabel('目标受众'),
          const SizedBox(height: 4),
          TextField(
            controller: _audienceCtrl,
            decoration: _inputDeco(hint: '例如：25-35岁都市白领'),
          ),
          const SizedBox(height: 14),

          // tone
          _buildFieldLabel('文章基调'),
          const SizedBox(height: 4),
          InputDecorator(
            decoration: _inputDeco(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _tone,
                isExpanded: true, isDense: true,
                items: _toneOptions.map((s) =>
                  DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => _tone = v!),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // purpose
          _buildFieldLabel('核心目的'),
          const SizedBox(height: 4),
          InputDecorator(
            decoration: _inputDeco(),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _purpose,
                isExpanded: true, isDense: true,
                items: _purposeOptions.map((p) =>
                  DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setState(() => _purpose = v!),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // generate button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 20),
              label: Text(_generating ? '生成中...' : '生成文案', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildHistoryTab(ThemeData theme, bool isDark) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final listHeight = constraints.maxHeight - 48;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Text('${_history.length} 条记录',
                    style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withAlpha(120))),
                  const Spacer(),
                  SizedBox(
                    height: 34,
                    child: FilledButton.tonalIcon(
                      onPressed: _loadHistory,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('刷新', style: TextStyle(fontSize: 15)),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: listHeight > 0 ? listHeight : 0,
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : _historyError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 40, color: Colors.red),
                              const SizedBox(height: 12),
                              Text('加载失败: $_historyError',
                                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(onPressed: _loadHistory, child: const Text('重试')),
                            ],
                          ),
                        )
                      : _history.isEmpty
                          ? Center(
                              child: Text('暂无生成记录',
                                style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))),
                            )
                          : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _history.length,
                          itemBuilder: (_, i) {
                            final h = _history[i];
                            final platform = h['platform_type'] as String? ?? 'wechat';
                            final topic = h['topic'] as String? ?? '';
                            final preview = h['content_preview'] as String? ?? '';
                            final model = h['model'] as String? ?? '';
                            final createdAt = h['created_at'] as String? ?? '';
                            final dt = createdAt.isNotEmpty
                                ? DateTime.tryParse(createdAt)?.toLocal()
                                : null;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _viewHistoryDetail(h),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(topic, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(6),
                                                color: AppTheme.purple.withAlpha(20),
                                              ),
                                              child: Text(_platformNames[platform] ?? platform,
                                                style: const TextStyle(fontSize: 11, color: AppTheme.purple, fontWeight: FontWeight.w600)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          preview.replaceAll('\n', ' '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, height: 1.5, color: theme.colorScheme.onSurface.withAlpha(150)),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.auto_awesome_rounded, size: 12, color: theme.colorScheme.onSurface.withAlpha(80)),
                                            const SizedBox(width: 4),
                                            Text(model,
                                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(100))),
                                            if (dt != null) ...[
                                              const SizedBox(width: 12),
                                              Text('${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                                                style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(100))),
                                            ],
                                            const Spacer(),
                                            GestureDetector(
                                              onTap: () => _editHistory(h),
                                              child: Container(
                                                width: 28, height: 28,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(6),
                                                  color: AppTheme.purple.withAlpha(15),
                                                ),
                                                child: const Icon(Icons.edit_rounded, size: 15, color: AppTheme.purple),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            GestureDetector(
                                              onTap: () => _deleteHistory(h['id']),
                                              child: Container(
                                                width: 28, height: 28,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(6),
                                                  color: AppTheme.red.withAlpha(15),
                                                ),
                                                child: const Icon(Icons.delete_outline_rounded, size: 15, color: AppTheme.red),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));
  }

  InputDecoration _inputDeco({String? hint}) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      filled: true,
      fillColor: Colors.grey.withAlpha(15),
    );
  }
}

// ── Full-screen preview page with MD/HTML toggle ──

class _CopyPreviewPage extends StatefulWidget {
  final String title;
  final String content;
  final String html;
  final String model;
  const _CopyPreviewPage({
    required this.title,
    required this.content,
    required this.html,
    required this.model,
  });

  @override
  State<_CopyPreviewPage> createState() => _CopyPreviewPageState();
}

class _CopyPreviewPageState extends State<_CopyPreviewPage> {
  bool _showHtml = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : const Color(0xFFF8F9FC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        centerTitle: false,
        actions: [
          if (widget.model.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.purple.withAlpha(20),
                ),
                child: Text(widget.model,
                  style: const TextStyle(fontSize: 12, color: AppTheme.purple, fontWeight: FontWeight.w600)),
              ),
            ),
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ToggleButtons(
                isSelected: [!_showHtml, _showHtml],
                onPressed: (i) => setState(() => _showHtml = i == 1),
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 30),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                selectedColor: Colors.white,
                fillColor: AppTheme.purple,
                color: AppTheme.purple.withAlpha(150),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Markdown')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('HTML')),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _showHtml && widget.html.isNotEmpty
          ? _HtmlView(html: widget.html, onClose: () => setState(() => _showHtml = false))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(
                widget.content,
                style: const TextStyle(fontSize: 15, height: 1.8),
              ),
            ),
    );
  }
}

class _HtmlView extends StatefulWidget {
  final String html;
  final VoidCallback? onClose;
  const _HtmlView({required this.html, this.onClose});

  @override
  State<_HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<_HtmlView> {
  WebviewController? _ctrl;
  final HtmlFrame _frame = HtmlFrame();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _ctrl = WebviewController();
      _ctrl!.loadStringContent(widget.html).then((_) {
        if (mounted) setState(() => _ready = true);
      }).catchError((e) {
        if (mounted) setState(() { _ready = true; _error = e.toString(); });
      });
      // timeout fallback after 5s
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_ready) setState(() => _ready = true);
      });
    } else {
      _frame.onClose = widget.onClose;
      _frame.show(widget.html);
      _ready = true;
    }
  }

  @override
  void didUpdateWidget(covariant _HtmlView old) {
    super.didUpdateWidget(old);
    if (kIsWeb && widget.html != old.html) {
      _frame.show(widget.html);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(
        child: SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (kIsWeb) {
      // IFrame is injected into the DOM — Flutter canvas sits behind it.
      return const SizedBox.shrink();
    }
    if (_ctrl != null && _error == null) {
      return Webview(_ctrl!);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(widget.html, style: const TextStyle(fontSize: 13)),
    );
  }
}
