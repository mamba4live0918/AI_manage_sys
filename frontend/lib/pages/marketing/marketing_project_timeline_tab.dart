import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import 'marketing_brief_preview_page.dart';

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
          builder: (_) => MarketingBriefPreviewPage(projectName: projectName, content: content, html: html, model: model),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
                          border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
                          boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
                        ),
                        child: ExpansionTile(
                          leading: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppTheme.purple)),
                            const SizedBox(width: 8),
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: AppTheme.purple.withAlpha(isDark ? 30 : 20),
                              ),
                              child: const Icon(Icons.folder_rounded, color: AppTheme.purple, size: 20),
                            ),
                          ]),
                          title: Text(p['name'] as String? ?? '',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13,
                                  color: isDark ? AppTheme.darkText : AppTheme.lightText)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: AppTheme.purple.withAlpha(isDark ? 25 : 18)),
                              child: Text(_stageLabels[stage] ?? stage,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth >= 400) {
                                    return Row(children: [
                                      Expanded(
                                        child: Material(
                                          color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () => _generateBrief(
                                                p['id'] as String, p['name'] as String? ?? ''),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                const Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.purple),
                                                const SizedBox(width: 6),
                                                const Text('AI 生成简报', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Material(
                                          color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () async {
                                              try {
                                                final resp = await _api.dio
                                                    .get('/marketing/projects/${p['id']}/timeline');
                                                final events = resp.data['events'] as List<dynamic>? ?? [];
                                                if (mounted) {
                                                  Navigator.push(context, MaterialPageRoute(
                                                    builder: (_) => _TimelineViewPage(
                                                      projectName: p['name'] as String? ?? '',
                                                      events: events,
                                                    ),
                                                  ));
                                                }
                                              } catch (_) {}
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                const Icon(Icons.timeline_rounded, size: 16, color: AppTheme.purple),
                                                const SizedBox(width: 6),
                                                const Text('时间轴', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ]);
                                  } else {
                                    return Column(children: [
                                      SizedBox(
                                        width: double.infinity,
                                        child: Material(
                                          color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () => _generateBrief(
                                                p['id'] as String, p['name'] as String? ?? ''),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                const Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.purple),
                                                const SizedBox(width: 6),
                                                const Text('AI 生成简报', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: Material(
                                          color: AppTheme.purple.withAlpha(isDark ? 25 : 18),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () async {
                                              try {
                                                final resp = await _api.dio
                                                    .get('/marketing/projects/${p['id']}/timeline');
                                                final events = resp.data['events'] as List<dynamic>? ?? [];
                                                if (mounted) {
                                                  Navigator.push(context, MaterialPageRoute(
                                                    builder: (_) => _TimelineViewPage(
                                                      projectName: p['name'] as String? ?? '',
                                                      events: events,
                                                    ),
                                                  ));
                                                }
                                              } catch (_) {}
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                const Icon(Icons.timeline_rounded, size: 16, color: AppTheme.purple),
                                                const SizedBox(width: 6),
                                                const Text('时间轴', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.purple)),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ]);
                                  }
                                },
                              ),
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
                final isDark = theme.brightness == Brightness.dark;
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
                    // Content card
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
                            border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
                            boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppTheme.purple)),
                                const SizedBox(width: 8),
                                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              ]),
                              const SizedBox(height: 4),
                              if (detail.isNotEmpty) ...[
                                Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                                const SizedBox(height: 4),
                              ],
                              Text(date.substring(0, 10),
                                  style: TextStyle(fontSize: 10, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}
