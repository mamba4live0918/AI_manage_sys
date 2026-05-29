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

  void _showDetail(Map<String, dynamic> approval) {
    final id = approval['id'] as String;
    final type = approval['approval_type'] as String? ?? 'leave';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.grey.shade300))),
              const SizedBox(height: 16),
              Text(_typeNames[type] ?? type, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (approval['applicant'] != null) ...[
                _buildApplicantCard(approval['applicant'], theme),
                const SizedBox(height: 12),
              ],
              if ((approval['content'] as String?)?.isNotEmpty == true) ...[
                Text(approval['content'] as String, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.check_rounded, size: 18, color: AppTheme.green),
                      label: const Text('通过', style: TextStyle(fontSize: 15, color: AppTheme.green, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.green),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () { Navigator.pop(ctx); _approve(id, 'approved'); },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.red),
                      label: const Text('驳回', style: TextStyle(fontSize: 15, color: AppTheme.red, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () { Navigator.pop(ctx); _approve(id, 'rejected'); },
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildApplicantCard(Map<String, dynamic> applicant, ThemeData theme) {
    final statusMap = {'active': '在职', 'inactive': '离职', 'probation': '试用期'};
    final empStatus = applicant['emp_status'] as String? ?? 'active';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 18, child: Text((applicant['username'] as String? ?? '?')[0].toUpperCase())),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(applicant['username'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(applicant['email'] ?? '', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(150))),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: empStatus == 'active' ? AppTheme.green.withAlpha(20) : empStatus == 'probation' ? AppTheme.orange.withAlpha(20) : AppTheme.red.withAlpha(20),
              ),
              child: Text(statusMap[empStatus] ?? empStatus, style: TextStyle(
                fontSize: 11,
                color: empStatus == 'active' ? AppTheme.green : empStatus == 'probation' ? AppTheme.orange : AppTheme.red,
              )),
            ),
          ]),
          if (applicant['department']?.isNotEmpty == true || applicant['position']?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (applicant['department']?.isNotEmpty == true) ...[
                Icon(Icons.business_rounded, size: 14, color: theme.colorScheme.onSurface.withAlpha(150)),
                const SizedBox(width: 4),
                Text(applicant['department'], style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(150))),
                const SizedBox(width: 12),
              ],
              if (applicant['position']?.isNotEmpty == true) ...[
                Icon(Icons.badge_rounded, size: 14, color: AppTheme.purple),
                const SizedBox(width: 4),
                Text(applicant['position'], style: const TextStyle(fontSize: 12, color: AppTheme.purple)),
              ],
            ]),
          ],
        ]),
      ),
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
                      final type = a['approval_type'] as String? ?? 'leave';
                      final status = a['status'] as String? ?? 'pending';

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
                              ]),
                              const SizedBox(height: 8),
                              if (a['applicant'] != null) ...[
                                Row(children: [
                                  const Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text('${a['applicant']['username']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
                                  if (a['applicant']['department'] != null && (a['applicant']['department'] as String).isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(a['applicant']['department'], style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(150))),
                                  ],
                                  if (a['applicant']['position'] != null && (a['applicant']['position'] as String).isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Text(a['applicant']['position'], style: TextStyle(fontSize: 11, color: AppTheme.purple)),
                                  ],
                                ]),
                                const SizedBox(height: 6),
                              ],
                              Text(a['content'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
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

