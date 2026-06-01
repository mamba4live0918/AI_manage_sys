import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _stageLabels = {
  'preparation': '准备阶段',
  'bidding': '投标中',
  'evaluation': '评标中',
  'negotiation': '商务谈判',
  'won': '中标',
  'lost': '未中标',
  'closed': '已关闭',
};

const _stageColors = {
  'preparation': AppTheme.blue,
  'bidding': AppTheme.orange,
  'evaluation': AppTheme.purple,
  'negotiation': AppTheme.teal,
  'won': AppTheme.green,
  'lost': AppTheme.red,
  'closed': Colors.grey,
};

class BiddingProcessTab extends StatefulWidget {
  const BiddingProcessTab({super.key});

  @override
  State<BiddingProcessTab> createState() => _BiddingProcessTabState();
}

class _BiddingProcessTabState extends State<BiddingProcessTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _processes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/bidding/processes', queryParameters: {'limit': 100});
      setState(() {
        _processes = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    String stage = 'preparation';
    final notesCtrl = TextEditingController();
    final deadlineCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('新建流程'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '项目名称 *')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(labelText: '当前阶段'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: stage, isExpanded: true, isDense: true,
                    items: _stageLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDlg(() => stage = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: deadlineCtrl, decoration: const InputDecoration(labelText: '截止日期 (YYYY-MM-DD)')),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '备注')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/bidding/processes', data: {
      'project_name': nameCtrl.text.trim(),
      'stage': stage,
      'deadline': deadlineCtrl.text.isNotEmpty ? deadlineCtrl.text : null,
      'notes': notesCtrl.text.trim(),
    });
    _load();
  }

  Future<void> _updateStage(String id, String newStage) async {
    await _api.dio.put('/bidding/processes/$id', data: {'stage': newStage});
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stages = ['preparation', 'bidding', 'evaluation', 'negotiation', 'won', 'lost', 'closed'];

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity, height: 40,
          child: ElevatedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建流程'),
          ),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _processes.isEmpty
                ? Center(child: Text('暂无流程', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: stages.map((stage) {
                        final items = _processes.where((p) => p['stage'] == stage).toList();
                        return Container(
                          width: 220,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: (_stageColors[stage] ?? Colors.grey).withAlpha(25),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.circle, size: 8, color: _stageColors[stage] ?? Colors.grey),
                                const SizedBox(width: 6),
                                Text(_stageLabels[stage] ?? stage, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _stageColors[stage] ?? Colors.grey)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: (_stageColors[stage] ?? Colors.grey).withAlpha(30),
                                  ),
                                  child: Text('${items.length}', style: TextStyle(fontSize: 11, color: _stageColors[stage] ?? Colors.grey)),
                                ),
                              ]),
                            ),
                            ...items.map((p) {
                              final deadline = p['deadline'] as String?;
                              final isOverdue = deadline != null && DateTime.tryParse(deadline)?.isBefore(DateTime.now()) == true;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _showDetail(p),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(p['project_name'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (deadline != null) ...[
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          Icon(Icons.access_time_rounded, size: 12, color: isOverdue ? AppTheme.red : theme.colorScheme.onSurface.withAlpha(120)),
                                          const SizedBox(width: 4),
                                          Text(deadline.substring(0, 10), style: TextStyle(fontSize: 11, color: isOverdue ? AppTheme.red : theme.colorScheme.onSurface.withAlpha(120))),
                                        ]),
                                      ],
                                      if ((p['notes'] as String? ?? '').isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(p['notes'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(120))),
                                      ],
                                      const SizedBox(height: 6),
                                      PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 16,
                                        icon: Icon(Icons.more_horiz_rounded, size: 16, color: theme.colorScheme.onSurface.withAlpha(120)),
                                        onSelected: (s) => _updateStage(p['id'] as String, s),
                                        itemBuilder: (_) => stages.where((s) => s != stage).map((s) => PopupMenuItem(
                                          value: s,
                                          child: Text('移到 ${_stageLabels[s] ?? s}', style: const TextStyle(fontSize: 13)),
                                        )).toList(),
                                      ),
                                    ]),
                                  ),
                                ),
                              );
                            }),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
      ),
    ]);
  }

  void _showDetail(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p['project_name'] as String? ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: (_stageColors[p['stage']] ?? Colors.grey).withAlpha(20),
              ),
              child: Text(_stageLabels[p['stage']] ?? p['stage'] ?? '', style: TextStyle(fontSize: 12, color: _stageColors[p['stage']] ?? Colors.grey)),
            ),
            const SizedBox(width: 12),
            if (p['deadline'] != null)
              Text('截止: ${p['deadline'].toString().substring(0, 10)}', style: const TextStyle(fontSize: 13)),
          ]),
          const SizedBox(height: 12),
          if ((p['notes'] as String? ?? '').isNotEmpty)
            Text(p['notes'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.6)),
        ]),
      ),
    );
  }
}
