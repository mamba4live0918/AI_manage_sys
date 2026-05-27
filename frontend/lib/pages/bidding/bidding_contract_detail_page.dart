import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
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

  Future<void> _showDiffPage(int v1, int v2) async {
    try {
      final resp = await _api.dio.get('/bidding/contracts/${widget.contractId}/diff',
        queryParameters: {'v1': v1, 'v2': v2});
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => BiddingContractDiffViewPage(diff: resp.data['diff'] as String? ?? ''),
        ));
      }
    } catch (_) {}
  }

  void _showDiffDialog() {
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
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showDiffPage(v1, v2);
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
                onPressed: _showDiffDialog,
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
}
