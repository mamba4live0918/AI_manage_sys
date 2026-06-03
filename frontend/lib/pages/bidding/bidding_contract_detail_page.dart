import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../widgets/signature_pad.dart';
import 'bidding_contract_diff_view.dart';

class BiddingContractDetailPage extends StatefulWidget {
  final String contractId;
  const BiddingContractDetailPage({super.key, required this.contractId});

  @override
  State<BiddingContractDetailPage> createState() => _BiddingContractDetailPageState();
}

class _BiddingContractDetailPageState extends State<BiddingContractDetailPage> {
  final _api = ApiClient();
  Map<String, dynamic>? _contract;
  List<Map<String, dynamic>> _versions = [];
  bool _loading = true;

  final _statusLabels = {'draft': '草稿', 'review': '审批中', 'pending_sign': '待签署', 'signed': '已签署', 'expired': '已过期', 'archived': '已归档'};
  final _statusColors = {
    'draft': Colors.grey, 'review': AppTheme.orange, 'pending_sign': AppTheme.blue,
    'signed': AppTheme.green, 'expired': AppTheme.red, 'archived': Colors.grey,
  };

  @override
  void initState() { super.initState(); _load(); }

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
    } catch (e) { setState(() => _loading = false); }
  }

  Future<void> _approve() async {
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('审批合同'), content: TextField(controller: commentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '审批意见（可选）')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('通过')),
      ],
    ));
    if (ok != true) return;
    try {
      await _api.dio.post('/bidding/contracts/${widget.contractId}/approve', data: {'action': 'approve', 'comment': commentCtrl.text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('合同已通过审批，进入签署阶段')));
      _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e'))); }
  }

  Future<void> _reject() async {
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('驳回合同'), content: TextField(controller: commentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '驳回原因')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppTheme.red), child: const Text('驳回')),
      ],
    ));
    if (ok != true) return;
    try {
      await _api.dio.post('/bidding/contracts/${widget.contractId}/approve', data: {'action': 'reject', 'comment': commentCtrl.text});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('合同已驳回')));
      _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e'))); }
  }

  Future<void> _submitReview() async {
    await _api.dio.put('/bidding/contracts/${widget.contractId}', data: {'status': 'review'});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已提交审批')));
    _load();
  }

  Future<void> _sign() async {
    final sigPadKey = GlobalKey();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('签署合同'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('请在下方签名：', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        SignaturePad(key: sigPadKey, onClear: () {}),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认签署')),
      ],
    ));
    if (ok != true) return;
    try {
      await _api.dio.put('/bidding/contracts/${widget.contractId}', data: {
        'status': 'signed',
        'signed_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('合同已签署')));
      _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('签署失败: $e'))); }
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('归档确认'), content: const Text('确定要归档此合同吗？归档后不可修改。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('归档')),
      ],
    ));
    if (ok != true) return;
    await _api.dio.put('/bidding/contracts/${widget.contractId}', data: {'status': 'archived'});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已归档')));
    _load();
  }

  Future<void> _showDiffPage(int v1, int v2) async {
    try {
      final resp = await _api.dio.get('/bidding/contracts/${widget.contractId}/diff', queryParameters: {'v1': v1, 'v2': v2});
      if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => BiddingContractDiffViewPage(diff: resp.data['diff'] as String? ?? '')));
    } catch (_) {}
  }

  void _showDiffDialog() {
    if (_versions.length < 2) return;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) {
      int v1 = _versions[1]['version_number'] as int? ?? 1; int v2 = _versions[0]['version_number'] as int? ?? 2;
      return AlertDialog(title: const Text('版本对比'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: '版本A'), child: DropdownButtonHideUnderline(child: DropdownButton<int>(value: v1, isExpanded: true, isDense: true, items: _versions.map((v) => DropdownMenuItem(value: v['version_number'] as int? ?? 0, child: Text('v${v['version_number']}'))).toList(), onChanged: (v) => setDlg(() => v1 = v!))))),
          const SizedBox(width: 12),
          Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: '版本B'), child: DropdownButtonHideUnderline(child: DropdownButton<int>(value: v2, isExpanded: true, isDense: true, items: _versions.map((v) => DropdownMenuItem(value: v['version_number'] as int? ?? 0, child: Text('v${v['version_number']}'))).toList(), onChanged: (v) => setDlg(() => v2 = v!))))),
        ]),
        const SizedBox(height: 12), SizedBox(height: 40, child: FilledButton(onPressed: () { Navigator.pop(ctx); _showDiffPage(v1, v2); }, child: const Text('查看差异'))),
      ]));
    }));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('合同详情')), body: const Center(child: CircularProgressIndicator()));
    if (_contract == null) return Scaffold(appBar: AppBar(title: const Text('合同详情')), body: const Center(child: Text('加载失败')));

    final c = _contract!; final content = c['content'] as String? ?? ''; final status = c['status'] as String? ?? 'draft';
    final statusColor = _statusColors[status] ?? Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: Text(c['title'] as String? ?? '合同详情', overflow: TextOverflow.ellipsis),
        actions: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: statusColor.withAlpha(30)),
            child: Text(_statusLabels[status] ?? status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(children: [
        // ── Action bar ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4, offset: const Offset(0, 2))]),
          child: Row(children: [
            _infoChip('对方', c['counterparty'] as String? ?? ''), const SizedBox(width: 8),
            _infoChip('版本', 'v${c['current_version']}'), const Spacer(),
            if (status == 'draft') ...[
              TextButton.icon(onPressed: _submitReview, icon: const Icon(Icons.send_rounded, size: 16), label: const Text('提交审批', style: TextStyle(fontSize: 13))),
            ] else if (status == 'review') ...[
              TextButton.icon(onPressed: _approve, icon: Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.green), label: Text('通过', style: TextStyle(fontSize: 13, color: AppTheme.green))),
              const SizedBox(width: 4),
              TextButton.icon(onPressed: _reject, icon: Icon(Icons.cancel_rounded, size: 16, color: AppTheme.red), label: Text('驳回', style: TextStyle(fontSize: 13, color: AppTheme.red))),
            ] else if (status == 'pending_sign') ...[
              FilledButton.icon(onPressed: _sign, icon: const Icon(Icons.edit_rounded, size: 16), label: const Text('签署合同', style: TextStyle(fontSize: 13)), style: FilledButton.styleFrom(backgroundColor: AppTheme.green)),
            ] else if (status == 'signed') ...[
              OutlinedButton.icon(onPressed: _archive, icon: const Icon(Icons.archive_rounded, size: 16), label: const Text('归档', style: TextStyle(fontSize: 13))),
            ],
            const SizedBox(width: 8),
            if (_versions.length >= 2) TextButton.icon(onPressed: _showDiffDialog, icon: const Icon(Icons.compare_rounded, size: 16), label: const Text('版本对比', style: TextStyle(fontSize: 13))),
          ]),
        ),
        // ── Content ──
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('合同内容', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8), SelectableText(content, style: const TextStyle(fontSize: 14, height: 1.8)),
          if (_versions.length > 1) ...[
            const SizedBox(height: 24), const Text('版本历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
            ..._versions.map((v) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
              title: Text('v${v['version_number']} — ${v['change_summary'] ?? ''}'),
              trailing: Text(v['created_at']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
            )),
          ],
        ]))),
      ]),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.grey.withAlpha(15)), child: Text('$label: $value', style: const TextStyle(fontSize: 12)));
  }
}
