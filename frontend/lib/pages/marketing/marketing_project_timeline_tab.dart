import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _stageLabels = {
  'initial_contact': '初步接触',
  'needs_assessment': '需求评估',
  'proposal': '方案提交',
  'negotiation': '商务谈判',
  'closed_won': '已成交',
  'closed_lost': '已流失',
};

class MarketingProjectTimelineTab extends StatefulWidget {
  const MarketingProjectTimelineTab({super.key});

  @override
  State<MarketingProjectTimelineTab> createState() => _MarketingProjectTimelineTabState();
}

class _MarketingProjectTimelineTabState extends State<MarketingProjectTimelineTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/marketing/projects', queryParameters: {'limit': 50});
      setState(() {
        _projects = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建项目'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '项目名称 *')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    await _api.dio.post('/marketing/projects', data: {'name': nameCtrl.text.trim()});
    _load();
  }

  Future<void> _generateBrief(String projectId, String projectName) async {
    try {
      final resp = await _api.dio.post('/marketing/projects/$projectId/brief', data: {});
      final content = resp.data['content'] as String? ?? '';
      final html = resp.data['content_html'] as String? ?? '';
      final model = resp.data['model'] as String? ?? '';
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => _BriefPreviewPage(projectName: projectName, content: content, html: html, model: model),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity, height: 40,
          child: ElevatedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建项目'),
          ),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _projects.isEmpty
                ? Center(child: Text('暂无项目', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _projects.length,
                    itemBuilder: (_, i) {
                      final p = _projects[i];
                      final stage = p['stage'] as String? ?? 'initial_contact';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.purple.withAlpha(20),
                            child: const Icon(Icons.folder_rounded, color: AppTheme.purple, size: 20),
                          ),
                          title: Text(p['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppTheme.purple.withAlpha(15)),
                            child: Text(_stageLabels[stage] ?? stage, style: const TextStyle(fontSize: 11, color: AppTheme.purple)),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 36,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _generateBrief(p['id'] as String, p['name'] as String? ?? ''),
                                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                                      label: const Text('AI 生成简报', style: TextStyle(fontSize: 13)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 36,
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      try {
                                        final resp = await _api.dio.get('/marketing/projects/${p['id']}/timeline');
                                        final events = resp.data['events'] as List<dynamic>? ?? [];
                                        if (mounted) {
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => _TimelineViewPage(projectName: p['name'] as String? ?? '', events: events),
                                          ));
                                        }
                                      } catch (_) {}
                                    },
                                    child: const Text('时间轴', style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}


// ── Brief Preview Page ──

class _BriefPreviewPage extends StatefulWidget {
  final String projectName;
  final String content;
  final String html;
  final String model;
  const _BriefPreviewPage({required this.projectName, required this.content, required this.html, required this.model});

  @override
  State<_BriefPreviewPage> createState() => _BriefPreviewPageState();
}

class _BriefPreviewPageState extends State<_BriefPreviewPage> {
  bool _showHtml = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName, overflow: TextOverflow.ellipsis),
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
          const SizedBox(width: 4),
        ],
      ),
      body: _showHtml && widget.html.isNotEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(widget.html, style: const TextStyle(fontSize: 13)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(widget.content, style: const TextStyle(fontSize: 15, height: 1.8)),
            ),
    );
  }
}


// ── Timeline View Page ──

class _TimelineViewPage extends StatelessWidget {
  final String projectName;
  final List<dynamic> events;
  const _TimelineViewPage({required this.projectName, required this.events});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('$projectName - 时间轴')),
      body: events.isEmpty
          ? Center(child: Text('暂无事件', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: events.length,
              itemBuilder: (_, i) {
                final e = events[i];
                final date = e['date'] as String? ?? '';
                final title = e['title'] as String? ?? '';
                final detail = e['detail'] as String? ?? '';
                final type = e['type'] as String? ?? '';
                return IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Timeline connector
                    SizedBox(
                      width: 40,
                      child: Column(children: [
                        Container(width: 2, height: 8, color: AppTheme.purple.withAlpha(60)),
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: type == 'brief' ? AppTheme.purple : AppTheme.purple.withAlpha(120),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            width: 2,
                            color: i < events.length - 1 ? AppTheme.purple.withAlpha(40) : Colors.transparent,
                          ),
                        ),
                      ]),
                    ),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(date.substring(0, 10), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
                          const SizedBox(height: 2),
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          if (detail.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(180))),
                          ],
                        ]),
                      ),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}
