import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
  String? _pdfUrl; // PDF预签名URL
  bool _showPDF = false;

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
      // 签完或归档后加载PDF
      final s = _contract?['status'] as String? ?? '';
      if (s == 'signed' || s == 'archived') _loadPdf();
    } catch (e) { setState(() => _loading = false); }
  }

  Future<void> _loadPdf() async {
    try {
      // 直接获取PDF bytes → 转 File → 上传给预览系统拿URL
      final token = _api.dio.options.headers['Authorization'] ?? '';
      final resp = await Dio().get(
        'http://localhost:8001/api/bidding/contracts/${widget.contractId}/pdf',
        options: Options(responseType: ResponseType.bytes, headers: {'Authorization': token}),
      );
      // 把PDF bytes上传到 /files/upload 拿 file_id → 再拿预览URL
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(resp.data, filename: 'contract_${widget.contractId}.pdf'),
      });
      final upResp = await _api.dio.post('/files/upload', data: formData);
      final fileId = upResp.data['id'] as String;
      final prevResp = await _api.dio.get('/preview/file/$fileId');
      setState(() { _pdfUrl = prevResp.data['url'] as String?; _showPDF = true; });
    } catch (_) {}
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
    try { await _api.dio.post('/bidding/contracts/${widget.contractId}/approve', data: {'action': 'approve', 'comment': commentCtrl.text}); _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e'))); }
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
    try { await _api.dio.post('/bidding/contracts/${widget.contractId}/approve', data: {'action': 'reject', 'comment': commentCtrl.text}); _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e'))); }
  }

  Future<void> _submitReview() async {
    await _api.dio.put('/bidding/contracts/${widget.contractId}', data: {'status': 'review'});
    _load();
  }

  Future<void> _sign() async {
    final sigPadKey = GlobalKey();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('签署合同'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('请手写签名：', style: TextStyle(fontSize: 13)),
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
      _loadPdf();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('签署失败: $e'))); }
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('归档确认'), content: const Text('确定要归档此合同吗？'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('归档'))],
    ));
    if (ok != true) return;
    await _api.dio.put('/bidding/contracts/${widget.contractId}', data: {'status': 'archived'});
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

    final c = _contract!; final status = c['status'] as String? ?? 'draft';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final signedAt = c['signed_at'] as String?;
    final isSigned = status == 'signed' || status == 'archived';

    return Scaffold(
      appBar: AppBar(
        title: Text(c['title'] as String? ?? '合同详情', overflow: TextOverflow.ellipsis),
        actions: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: statusColor.withAlpha(30)),
            child: Text(_statusLabels[status] ?? status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),),
        ],
      ),
      body: Column(children: [
        // Action bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: theme.colorScheme.surface, boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4, offset: const Offset(0, 2))]),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            _infoChip('对方', c['counterparty'] as String? ?? ''),
            _infoChip('版本', 'v${c['current_version']}'),
            if (signedAt != null)
              _infoChip('签署于', signedAt.substring(0, 10)),
            const Spacer(),
            if (status == 'draft')
              TextButton.icon(onPressed: _submitReview, icon: const Icon(Icons.send_rounded, size: 16), label: const Text('提交审批', style: TextStyle(fontSize: 13)))
            else if (status == 'review') ...[
              TextButton.icon(onPressed: _approve, icon: Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.green), label: Text('通过', style: TextStyle(fontSize: 13, color: AppTheme.green))),
              TextButton.icon(onPressed: _reject, icon: Icon(Icons.cancel_rounded, size: 16, color: AppTheme.red), label: Text('驳回', style: TextStyle(fontSize: 13, color: AppTheme.red))),
            ] else if (status == 'pending_sign')
              FilledButton.icon(onPressed: _sign, icon: const Icon(Icons.edit_rounded, size: 16), label: const Text('签署合同', style: TextStyle(fontSize: 13)), style: FilledButton.styleFrom(backgroundColor: AppTheme.green))
            else if (status == 'signed')
              OutlinedButton.icon(onPressed: _archive, icon: const Icon(Icons.archive_rounded, size: 16), label: const Text('归档', style: TextStyle(fontSize: 13))),
            if (_versions.length >= 2) TextButton.icon(onPressed: _showDiffDialog, icon: const Icon(Icons.compare_rounded, size: 16), label: const Text('版本对比', style: TextStyle(fontSize: 13))),
          ]),
        ),
        // Content: PDF preview (signed/archived) or text
        Expanded(
          child: _showPDF && _pdfUrl != null
              ? _PdfEmbedView(url: _pdfUrl!)
              : SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('合同内容', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SelectableText(c['content'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.8)),
                  // 签署信息
                  if (isSigned) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.green.withAlpha(80)), color: AppTheme.green.withAlpha(10)),
                      child: Column(children: [
                        const Icon(Icons.check_circle_rounded, size: 32, color: AppTheme.green),
                        const SizedBox(height: 8),
                        const Text('已签署', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.green)),
                        if (signedAt != null) ...[
                          const SizedBox(height: 4),
                          Text('签署时间: ${signedAt.substring(0, 19).replaceAll('T', ' ')}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ]),
                    ),
                  ],
                  if (_versions.length > 1) ...[
                    const SizedBox(height: 24), const Text('版本历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
                    ..._versions.map((v) => ListTile(contentPadding: EdgeInsets.zero, dense: true,
                      title: Text('v${v['version_number']} — ${v['change_summary'] ?? ''}'),
                      trailing: Text(v['created_at']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
                    )),
                  ],
                ])),
        ),
      ]),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.grey.withAlpha(15)), child: Text('$label: $value', style: const TextStyle(fontSize: 12)));
  }
}

// PDF内嵌预览（用 iframe）
class _PdfEmbedView extends StatefulWidget {
  final String url;
  const _PdfEmbedView({required this.url});
  @override
  State<_PdfEmbedView> createState() => _PdfEmbedViewState();
}

class _PdfEmbedViewState extends State<_PdfEmbedView> {
  late final WebViewWidget _webView;

  @override
  void initState() {
    super.initState();
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadRequest(Uri.parse(widget.url));
    _webView = WebViewWidget(controller: ctrl);
  }

  @override
  Widget build(BuildContext context) => _webView;
}
