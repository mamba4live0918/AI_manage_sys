import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _typeNames = {'leave': '请假', 'expense': '报销', 'regularization': '转正'};
const _statusNames = {'pending': '待审批', 'approved': '已通过', 'rejected': '已驳回'};
const _levelLabels = {1: '一级审批', 2: '二级审批', 3: '三级审批'};

class HrApprovalTab extends StatefulWidget {
  const HrApprovalTab({super.key});

  @override
  State<HrApprovalTab> createState() => _HrApprovalTabState();
}

class _HrApprovalTabState extends State<HrApprovalTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _approvals = [];
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
      final params = <String, dynamic>{'limit': 100};
      if (_statusFilter.isNotEmpty) params['status'] = _statusFilter;
      final resp = await _api.dio.get('/hr/approvals', queryParameters: params);
      setState(() {
        _approvals = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final contentCtrl = TextEditingController();
    String type = 'leave';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('发起审批'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InputDecorator(
                decoration: const InputDecoration(labelText: '类型'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: type, isExpanded: true, isDense: true,
                    items: _typeNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDlg(() => type = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: contentCtrl, maxLines: 4, decoration: const InputDecoration(labelText: '内容')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('提交')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _api.dio.post('/hr/approvals', data: {
      'approval_type': type,
      'content': contentCtrl.text.trim(),
    });
    _load();
  }

  Future<void> _approve(String id, String action) async {
    final commentCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == 'approved' ? '审批通过' : '审批驳回'),
        content: TextField(controller: commentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '批注')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (ok != true) return;

    await _api.dio.put('/hr/approvals/$id', data: {
      'status': action,
      'comment': commentCtrl.text.trim(),
    });
    _load();
  }

  Future<void> _approveStep(String approvalId, String stepId, String action) async {
    final commentCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == 'approved' ? '审批步骤通过' : '审批步骤驳回'),
        content: TextField(controller: commentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '批注')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (ok != true) return;

    await _api.dio.put('/hr/approvals/$approvalId/steps/$stepId', data: {
      'status': action,
      'comment': commentCtrl.text.trim(),
    });
    _load();
  }

  void _showDetail(Map<String, dynamic> approval) {
    final id = approval['id'] as String;
    final type = approval['approval_type'] as String? ?? 'leave';
    final status = approval['status'] as String? ?? 'pending';
    final steps = approval['steps'] as List<dynamic>? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.grey.shade300))),
              const SizedBox(height: 16),
              Text(_typeNames[type] ?? type, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(approval['content'] as String? ?? '', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text('审批流程', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: steps.map((s) {
                    final stepStatus = s['status'] as String? ?? 'pending';
                    final level = s['level'] as int? ?? 1;
                    final comment = s['comment'] as String? ?? '';
                    final stepId = s['id'] as String;
                    final isPending = stepStatus == 'pending';
                    final isApproved = stepStatus == 'approved';
                    final color = isApproved ? AppTheme.green : isPending ? AppTheme.orange : AppTheme.red;
                    final icon = isApproved ? Icons.check_circle_rounded : isPending ? Icons.radio_button_unchecked_rounded : Icons.cancel_rounded;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          Icon(icon, color: color, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_levelLabels[level] ?? '第${level}级', style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (comment.isNotEmpty) Text(comment, maxLines: 2, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(150))),
                            ]),
                          ),
                          if (isPending && status == 'pending')
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                icon: const Icon(Icons.check_rounded, color: AppTheme.green, size: 20),
                                onPressed: () { Navigator.pop(ctx); _approveStep(id, stepId, 'approved'); },
                                tooltip: '通过',
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: AppTheme.red, size: 20),
                                onPressed: () { Navigator.pop(ctx); _approveStep(id, stepId, 'rejected'); },
                                tooltip: '驳回',
                              ),
                            ]),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(height: 40, child: ElevatedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('发起审批'),
            )),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: ['', 'pending', 'approved', 'rejected'].map((s) {
            final selected = _statusFilter == s;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(s.isEmpty ? '全部' : _statusNames[s] ?? s),
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
            : _approvals.isEmpty
                ? Center(child: Text('暂无审批', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _approvals.length,
                    itemBuilder: (_, i) {
                      final a = _approvals[i];
                      final id = a['id'] as String;
                      final type = a['approval_type'] as String? ?? 'leave';
                      final status = a['status'] as String? ?? 'pending';
                      final steps = a['steps'] as List<dynamic>? ?? [];
                      final pendingCount = steps.where((s) => s['status'] == 'pending').length;
                      final totalSteps = steps.length;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showDetail(a),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: AppTheme.purple.withAlpha(20)),
                                  child: Text(_typeNames[type] ?? type, style: const TextStyle(fontSize: 11, color: AppTheme.purple)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    color: status == 'approved' ? AppTheme.green.withAlpha(20) : status == 'rejected' ? AppTheme.red.withAlpha(20) : AppTheme.orange.withAlpha(20),
                                  ),
                                  child: Text(_statusNames[status] ?? status, style: TextStyle(
                                    fontSize: 11,
                                    color: status == 'approved' ? AppTheme.green : status == 'rejected' ? AppTheme.red : AppTheme.orange,
                                  )),
                                ),
                                const Spacer(),
                                if (status == 'pending')
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                                    onSelected: (action) => _approve(id, action),
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'approved', child: Text('通过', style: TextStyle(color: AppTheme.green))),
                                      const PopupMenuItem(value: 'rejected', child: Text('驳回', style: TextStyle(color: AppTheme.red))),
                                    ],
                                  ),
                              ]),
                              const SizedBox(height: 8),
                              Text(a['content'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                              if (totalSteps > 0) ...[
                                const SizedBox(height: 10),
                                Row(children: [
                                  for (int j = 0; j < totalSteps; j++) ...[
                                    if (j > 0) ...[
                                      const SizedBox(width: 4),
                                      Expanded(flex: 0, child: Container(width: 16, height: 2, color: Colors.grey.shade300)),
                                      const SizedBox(width: 4),
                                    ],
                                    _StepDot(
                                      step: steps[j] as Map<String, dynamic>,
                                      label: '${j + 1}级',
                                    ),
                                  ],
                                  const SizedBox(width: 12),
                                  Text('$pendingCount/$totalSteps 待审批', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(150))),
                                ]),
                              ],
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class _StepDot extends StatelessWidget {
  final Map<String, dynamic> step;
  final String label;

  const _StepDot({required this.step, required this.label});

  @override
  Widget build(BuildContext context) {
    final status = step['status'] as String? ?? 'pending';
    final color = status == 'approved' ? AppTheme.green : status == 'rejected' ? AppTheme.red : Colors.grey.shade400;

    return Column(children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: color, width: 2)),
        child: status == 'approved'
            ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
            : status == 'rejected'
                ? const Icon(Icons.close_rounded, size: 12, color: Colors.white)
                : null,
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 9, color: color)),
    ]);
  }
}
