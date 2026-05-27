import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import 'bidding_contract_detail_page.dart';
import 'bidding_contract_generate_page.dart';

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
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BiddingContractGeneratePage(templates: _templates)),
    );
    _load();
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
                              builder: (_) => BiddingContractDetailPage(contractId: id),
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
