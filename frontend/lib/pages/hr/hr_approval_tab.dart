import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

const _typeNames = {'leave': '请假', 'expense': '报销', 'regularization': '转正'};
const _statusNames = {'pending': '待审批', 'approved': '已通过', 'rejected': '已驳回'};

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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFF3E8FF),
                            child: Icon(Icons.fact_check_rounded, color: AppTheme.purple, size: 20),
                          ),
                          title: Text(_typeNames[type] ?? type, maxLines: 1),
                          subtitle: Text(a['content'] as String? ?? '', maxLines: 2),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: AppTheme.purple.withAlpha(20)),
                              child: Text(_statusNames[status] ?? status, style: const TextStyle(fontSize: 11, color: AppTheme.purple)),
                            ),
                            if (status == 'pending') ...[
                              const SizedBox(width: 4),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, size: 18),
                                onSelected: (action) => _approve(id, action),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'approved', child: Text('通过', style: TextStyle(color: AppTheme.green))),
                                  const PopupMenuItem(value: 'rejected', child: Text('驳回', style: TextStyle(color: AppTheme.red))),
                                ],
                              ),
                            ],
                          ]),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
