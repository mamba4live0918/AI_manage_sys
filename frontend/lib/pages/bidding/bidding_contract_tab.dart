import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class BiddingContractTab extends StatefulWidget {
  const BiddingContractTab({super.key});

  @override
  State<BiddingContractTab> createState() => _BiddingContractTabState();
}

class _BiddingContractTabState extends State<BiddingContractTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _contracts = [];
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final contracts = await _api.dio.get('/bidding/contracts', queryParameters: {'limit': 50});
      final templates = await _api.dio.get('/bidding/templates', queryParameters: {'limit': 100});
      setState(() {
        _contracts = List<Map<String, dynamic>>.from(contracts.data['items']);
        _templates = List<Map<String, dynamic>>.from(templates.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    String? selectedTemplateId;
    final titleCtrl = TextEditingController();
    final counterpartyCtrl = TextEditingController();
    final varsCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('生成合同'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InputDecorator(
                decoration: const InputDecoration(labelText: '合同模板 (可选)'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedTemplateId,
                    isExpanded: true, isDense: true,
                    hint: const Text('选择模板或直接输入'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('不使用模板')),
                      ..._templates.map((t) => DropdownMenuItem(
                        value: t['id'] as String?,
                        child: Text(t['name'] as String? ?? ''),
                      )),
                    ],
                    onChanged: (v) => setDlg(() => selectedTemplateId = v),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '合同标题 *')),
              const SizedBox(height: 8),
              TextField(controller: counterpartyCtrl, decoration: const InputDecoration(labelText: '对方名称')),
              const SizedBox(height: 8),
              TextField(controller: varsCtrl, maxLines: 2, decoration: const InputDecoration(
                labelText: '变量替换', hintText: 'key1: value1, key2: value2',
              )),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('生成')),
          ],
        ),
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;

    final Map<String, String> vars = {};
    for (final part in varsCtrl.text.split(',')) {
      final kv = part.trim().split(':');
      if (kv.length == 2) vars[kv[0].trim()] = kv[1].trim();
    }

    setState(() => _loading = true);
    try {
      final resp = await _api.dio.post('/bidding/contracts', data: {
        'template_id': selectedTemplateId,
        'title': titleCtrl.text.trim(),
        'counterparty': counterpartyCtrl.text.trim(),
        'variables': vars,
      });
      _load();
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _ContractDetailPage(contractId: resp.data['id'] as String),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
    setState(() => _loading = false);
  }

  Future<void> _delete(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除合同'),
        content: Text('确定要删除"$title"吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/bidding/contracts/$id');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabels = {'draft': '草稿', 'pending': '待签署', 'signed': '已签署', 'expired': '已过期', 'archived': '已归档'};

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(height: 40, child: ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('生成合同'),
            )),
          ),
          const SizedBox(width: 8),
          SizedBox(height: 40, child: OutlinedButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => _TemplateListPage(templates: _templates, onChanged: _load),
              ));
            },
            child: const Text('模板管理'),
          )),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'draft', 'pending', 'signed', 'expired'].map((s) {
            final selected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s.isEmpty ? '全部' : statusLabels[s] ?? s),
                selected: selected,
                onSelected: (_) { _statusFilter = selected ? '' : s; _load(); },
              ),
            );
          }).toList()),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _contracts.isEmpty
                ? Center(child: Text('暂无合同', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _contracts.length,
                    itemBuilder: (_, i) {
                      final c = _contracts[i];
                      final id = c['id'] as String;
                      final title = c['title'] as String? ?? '';
                      final counterparty = c['counterparty'] as String? ?? '';
                      final status = c['status'] as String? ?? 'draft';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFF3E8FF),
                            child: Icon(Icons.article_rounded, color: AppTheme.purple, size: 20),
                          ),
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text([counterparty, 'v${c['current_version']}'].where((s) => s.isNotEmpty).join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: AppTheme.purple.withAlpha(20),
                              ),
                              child: Text(statusLabels[status] ?? status, style: const TextStyle(fontSize: 11, color: AppTheme.purple)),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18),
                              onSelected: (action) {
                                if (action == 'delete') _delete(id, title);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                              ],
                            ),
                          ]),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => _ContractDetailPage(contractId: id),
                            ));
                          },
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}


// ── Contract Detail Page ──

class _ContractDetailPage extends StatefulWidget {
  final String contractId;
  const _ContractDetailPage({required this.contractId});

  @override
  State<_ContractDetailPage> createState() => _ContractDetailPageState();
}

class _ContractDetailPageState extends State<_ContractDetailPage> {
  final _api = ApiClient();
  Map<String, dynamic>? _contract;
  List<Map<String, dynamic>> _versions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final contractResp = await _api.dio.get('/bidding/contracts/${widget.contractId}');
      final versionsResp = await _api.dio.get('/bidding/contracts/${widget.contractId}/versions');
      setState(() {
        _contract = contractResp.data;
        _versions = List<Map<String, dynamic>>.from(versionsResp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusLabels = {'draft': '草稿', 'pending': '待签署', 'signed': '已签署', 'expired': '已过期', 'archived': '已归档'};
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('合同详情')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_contract == null) {
      return Scaffold(appBar: AppBar(title: const Text('合同详情')), body: const Center(child: Text('加载失败')));
    }

    final c = _contract!;
    final content = c['content'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(c['title'] as String? ?? '合同详情', overflow: TextOverflow.ellipsis),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppTheme.purple.withAlpha(20)),
            child: Text(statusLabels[c['status']] ?? c['status'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.purple)),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _infoChip('对方', c['counterparty'] as String? ?? ''),
            const SizedBox(width: 8),
            _infoChip('版本', 'v${c['current_version']}'),
            const Spacer(),
            if (_versions.length >= 2)
              TextButton.icon(
                onPressed: () => _showDiffDialog(context),
                icon: const Icon(Icons.compare_rounded, size: 16),
                label: const Text('版本对比', style: TextStyle(fontSize: 13)),
              ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('合同内容', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              // Markdown content with basic formatting
              SelectableText(content, style: const TextStyle(fontSize: 14, height: 1.8)),
              if (_versions.length > 1) ...[
                const SizedBox(height: 24),
                const Text('版本历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ..._versions.map((v) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('v${v['version_number']} — ${v['change_summary'] ?? ''}'),
                  trailing: Text(v['created_at']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
                )),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.grey.withAlpha(15)),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }

  void _showDiffDialog(BuildContext context) {
    if (_versions.length < 2) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) {
          int v1 = _versions[1]['version_number'] as int? ?? 1;
          int v2 = _versions[0]['version_number'] as int? ?? 2;
          return AlertDialog(
            title: const Text('版本对比'),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: InputDecorator(
                  decoration: const InputDecoration(labelText: '版本A'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: v1, isExpanded: true, isDense: true,
                      items: _versions.map((v) => DropdownMenuItem(
                        value: v['version_number'] as int? ?? 0,
                        child: Text('v${v['version_number']}'),
                      )).toList(),
                      onChanged: (v) => setDlg(() => v1 = v!),
                    ),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: InputDecorator(
                  decoration: const InputDecoration(labelText: '版本B'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: v2, isExpanded: true, isDense: true,
                      items: _versions.map((v) => DropdownMenuItem(
                        value: v['version_number'] as int? ?? 0,
                        child: Text('v${v['version_number']}'),
                      )).toList(),
                      onChanged: (v) => setDlg(() => v2 = v!),
                    ),
                  ),
                )),
              ]),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      final resp = await _api.dio.get('/bidding/contracts/${widget.contractId}/diff', queryParameters: {'v1': v1, 'v2': v2});
                      if (mounted) {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => _DiffViewPage(diff: resp.data['diff'] as String? ?? ''),
                        ));
                      }
                    } catch (_) {}
                  },
                  child: const Text('查看差异'),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}


// ── Diff View Page ──

class _DiffViewPage extends StatelessWidget {
  final String diff;
  const _DiffViewPage({required this.diff});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('版本差异')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF1E1E1E),
          ),
          child: SelectableText(
            diff.isEmpty ? '无差异' : diff,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: Color(0xFFD4D4D4),
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}


// ── Template List Page ──

class _TemplateListPage extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  final VoidCallback? onChanged;
  const _TemplateListPage({required this.templates, this.onChanged});

  @override
  State<_TemplateListPage> createState() => _TemplateListPageState();
}

class _TemplateListPageState extends State<_TemplateListPage> {
  final _api = ApiClient();
  late List<Map<String, dynamic>> _templates;

  @override
  void initState() {
    super.initState();
    _templates = List.from(widget.templates);
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController(text: 'service');
    final contentCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建模板'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '模板名称 *')),
            const SizedBox(height: 8),
            TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: '合同类型')),
            const SizedBox(height: 8),
            TextField(controller: contentCtrl, maxLines: 6, decoration: const InputDecoration(labelText: '模板内容 (Markdown)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/bidding/templates', data: {
      'name': nameCtrl.text.trim(),
      'type': typeCtrl.text.trim(),
      'content': contentCtrl.text.trim(),
    });
    widget.onChanged?.call();
    final resp = await _api.dio.get('/bidding/templates', queryParameters: {'limit': 100});
    setState(() { _templates = List<Map<String, dynamic>>.from(resp.data['items']); });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('合同模板管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建模板'),
      ),
      body: _templates.isEmpty
          ? Center(child: Text('暂无模板', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _templates.length,
              itemBuilder: (_, i) {
                final t = _templates[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFF3E8FF),
                      child: Icon(Icons.description_rounded, color: AppTheme.purple, size: 20),
                    ),
                    title: Text(t['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t['type'] as String? ?? '', maxLines: 1),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                    onTap: () async {
                      final resp = await _api.dio.get('/bidding/templates/${t['id']}');
                      final full = resp.data;
                      if (mounted) {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(title: Text(full['name'] as String? ?? '模板详情')),
                            body: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('类型: ${full['type'] ?? ''}', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(120))),
                                const SizedBox(height: 12),
                                SelectableText(full['content'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.8)),
                              ]),
                            ),
                          ),
                        ));
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
