import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class MarketingProposalTab extends StatefulWidget {
  const MarketingProposalTab({super.key});

  @override
  State<MarketingProposalTab> createState() => _MarketingProposalTabState();
}

class _MarketingProposalTabState extends State<MarketingProposalTab> {
  final _api = ApiClient();
  final _titleCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();
  final _reqCtrl = TextEditingController();

  List<Map<String, dynamic>> _proposals = [];
  List<Map<String, dynamic>> _customers = [];
  String? _selectedCustomerId;
  bool _generating = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _topicCtrl.dispose();
    _reqCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final props = await _api.dio.get('/marketing/proposals', queryParameters: {'limit': 50});
      final custs = await _api.dio.get('/marketing/customers', queryParameters: {'limit': 200});
      setState(() {
        _proposals = List<Map<String, dynamic>>.from(props.data['items']);
        _customers = List<Map<String, dynamic>>.from(custs.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写方案标题')));
      return;
    }
    setState(() => _generating = true);
    try {
      final resp = await _api.dio.post('/marketing/proposals/generate', data: {
        'customer_id': _selectedCustomerId,
        'title': _titleCtrl.text.trim(),
        'topic': _topicCtrl.text.trim(),
        'requirements': _reqCtrl.text.trim(),
      });
      final content = resp.data['content'] as String? ?? '';
      final html = resp.data['content_html'] as String? ?? '';
      final model = resp.data['model'] as String? ?? '';
      _load();
      if (mounted) {
        _showPreview(_titleCtrl.text.trim(), content, html, model);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
    setState(() => _generating = false);
  }

  void _showPreview(String title, String content, String html, String model) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ProposalPreviewPage(title: title, content: content, html: html, model: model),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Generate section
        const Text('生成营销方案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(labelText: '目标客户 (可选)'),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedCustomerId,
              isExpanded: true, isDense: true,
              hint: const Text('选择客户'),
              items: [
                const DropdownMenuItem(value: null, child: Text('通用方案 (无指定客户)')),
                ..._customers.map((c) => DropdownMenuItem(
                  value: c['id'] as String?,
                  child: Text(c['name'] as String? ?? ''),
                )),
              ],
              onChanged: (v) => setState(() => _selectedCustomerId = v),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _titleCtrl, decoration: const InputDecoration(labelText: '方案标题 *', hintText: '例如：XX客户品牌营销方案')),
        const SizedBox(height: 10),
        TextField(controller: _topicCtrl, decoration: const InputDecoration(labelText: '主题', hintText: '例如：品牌推广')),
        const SizedBox(height: 10),
        TextField(controller: _reqCtrl, maxLines: 4, decoration: const InputDecoration(labelText: '需求描述', hintText: '描述具体的营销需求和目标...')),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity, height: 48,
          child: FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome_rounded, size: 20),
            label: Text(_generating ? '生成中...' : '生成方案', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 24),

        // History list
        Row(children: [
          Text('已生成 ${_proposals.length} 份方案', style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withAlpha(120))),
          const Spacer(),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('刷新', style: TextStyle(fontSize: 13))),
        ]),
        const SizedBox(height: 8),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_proposals.isEmpty)
          Center(child: Text('暂无方案', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
        else
          ..._proposals.map((p) {
            final statusLabels = {'draft': '草稿', 'final': '定稿', 'archived': '已归档'};
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3E8FF),
                  child: Icon(Icons.description_rounded, color: AppTheme.purple, size: 20),
                ),
                title: Text(p['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(p['content_preview'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppTheme.purple.withAlpha(20)),
                  child: Text(statusLabels[p['status']] ?? p['status'] ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.purple)),
                ),
                onTap: () async {
                  try {
                    final resp = await _api.dio.get('/marketing/proposals/${p['id']}');
                    final d = resp.data;
                    if (mounted) _showPreview(d['title'] ?? '', d['content'] ?? '', d['content_html'] ?? '', '');
                  } catch (_) {}
                },
              ),
            );
          }),
      ]),
    );
  }
}


// ── Proposal Preview Page ──

class _ProposalPreviewPage extends StatefulWidget {
  final String title;
  final String content;
  final String html;
  final String model;
  const _ProposalPreviewPage({required this.title, required this.content, required this.html, required this.model});

  @override
  State<_ProposalPreviewPage> createState() => _ProposalPreviewPageState();
}

class _ProposalPreviewPageState extends State<_ProposalPreviewPage> {
  bool _showHtml = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.model.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppTheme.purple.withAlpha(20)),
                child: Text(widget.model, style: const TextStyle(fontSize: 12, color: AppTheme.purple)),
              ),
            ),
          if (widget.html.isNotEmpty)
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
          ? _ProposalHtmlView(html: widget.html)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(widget.content, style: const TextStyle(fontSize: 15, height: 1.8)),
            ),
    );
  }
}

class _ProposalHtmlView extends StatefulWidget {
  final String html;
  const _ProposalHtmlView({required this.html});

  @override
  State<_ProposalHtmlView> createState() => _ProposalHtmlViewState();
}

class _ProposalHtmlViewState extends State<_ProposalHtmlView> {
  WebviewController? _ctrl;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    if (!kIsWeb) {
      try {
        _ctrl = WebviewController();
        await _ctrl!.initialize();
        await _ctrl!.loadStringContent(widget.html);
        if (mounted) setState(() => _ready = true);
      } catch (e) {
        if (mounted) setState(() { _ready = true; _error = e.toString(); });
      }
    } else {
      if (mounted) setState(() { _ready = true; _error = 'Web端不支持HTML预览，请使用桌面客户端'; });
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready && _error == null) {
      return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(widget.html, style: const TextStyle(fontSize: 13)),
      );
    }
    if (kIsWeb) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(widget.html, style: const TextStyle(fontSize: 13)),
      );
    }
    return Webview(_ctrl!);
  }
}
