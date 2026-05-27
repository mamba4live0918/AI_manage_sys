import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class PmProjectDetailPage extends StatefulWidget {
  final String projectId;
  const PmProjectDetailPage({super.key, required this.projectId});

  @override
  State<PmProjectDetailPage> createState() => _PmProjectDetailPageState();
}

class _PmProjectDetailPageState extends State<PmProjectDetailPage> {
  final _api = ApiClient();
  Map<String, dynamic>? _project;
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await _api.dio.get('/pm/projects/${widget.projectId}');
      final logs = await _api.dio.get('/pm/projects/${widget.projectId}/logs', queryParameters: {'limit': 20});
      setState(() {
        _project = p.data;
        _logs = List<Map<String, dynamic>>.from(logs.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _generateReport() async {
    final typeCtrl = TextEditingController(text: 'progress');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('生成报告'),
        content: TextField(controller: typeCtrl, decoration: const InputDecoration(labelText: '报告类型')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('生成')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final resp = await _api.dio.post('/pm/projects/${widget.projectId}/report', data: {
        'report_type': typeCtrl.text.trim(),
      });
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('报告已生成'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: SingleChildScrollView(
                child: SelectableText(resp.data['content'] as String? ?? ''),
              ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const stageNames = {
      'initiation': '启动', 'planning': '规划', 'execution': '执行',
      'monitoring': '监控', 'closure': '收尾',
    };

    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('项目详情')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_project == null) {
      return Scaffold(appBar: AppBar(title: const Text('项目详情')), body: const Center(child: Text('加载失败')));
    }

    final p = _project!;
    final stage = p['stage'] as String? ?? 'initiation';
    final budget = p['budget'] as num? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(p['name'] as String? ?? '项目详情', overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: _generateReport,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('生成报告', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: AppTheme.blue.withAlpha(20)),
              child: Text(stageNames[stage] ?? stage, style: const TextStyle(fontSize: 12, color: AppTheme.blue)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.grey.withAlpha(15)),
              child: Text('预算: \$${budget.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 16),
          if ((p['description'] as String? ?? '').isNotEmpty) ...[
            const Text('项目描述', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SelectableText(p['description'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.8)),
            const SizedBox(height: 24),
          ],
          if (_logs.isNotEmpty) ...[
            const Text('近期走访', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._logs.take(10).map((l) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.location_on_rounded, size: 18, color: AppTheme.blue),
              title: Text(l['location'] as String? ?? '', style: const TextStyle(fontSize: 13)),
              subtitle: Text(l['content'] as String? ?? '', maxLines: 2, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
              trailing: Text((l['visited_at'] as String? ?? '').substring(0, 10), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(100))),
            )),
          ],
        ]),
      ),
    );
  }
}
