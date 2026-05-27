import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import 'bidding_contract_detail_page.dart';

class BiddingContractGeneratePage extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  const BiddingContractGeneratePage({super.key, required this.templates});

  @override
  State<BiddingContractGeneratePage> createState() => _BiddingContractGeneratePageState();
}

class _BiddingContractGeneratePageState extends State<BiddingContractGeneratePage> {
  final _api = ApiClient();
  final _titleCtrl = TextEditingController();
  final _counterpartyCtrl = TextEditingController();
  final _varsCtrl = TextEditingController();
  String? _templateId;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _counterpartyCtrl.dispose();
    _varsCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入合同标题')));
      return;
    }

    final Map<String, String> vars = {};
    for (final part in _varsCtrl.text.split(',')) {
      final kv = part.trim().split(':');
      if (kv.length == 2) vars[kv[0].trim()] = kv[1].trim();
    }

    setState(() => _loading = true);
    try {
      final resp = await _api.dio.post('/bidding/contracts', data: {
        'template_id': _templateId,
        'title': _titleCtrl.text.trim(),
        'counterparty': _counterpartyCtrl.text.trim(),
        'variables': vars,
      });
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => BiddingContractDetailPage(contractId: resp.data['id'] as String),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败: $e')));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生成合同')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                InputDecorator(
                  decoration: const InputDecoration(labelText: '合同模板 (可选)'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _templateId,
                      isExpanded: true, isDense: true,
                      hint: const Text('选择模板或直接输入'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('不使用模板')),
                        ...widget.templates.map((t) => DropdownMenuItem(
                          value: t['id'] as String?,
                          child: Text(t['name'] as String? ?? ''),
                        )),
                      ],
                      onChanged: (v) => setState(() => _templateId = v),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: '合同标题 *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _counterpartyCtrl,
                  decoration: const InputDecoration(labelText: '对方名称', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _varsCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '变量替换',
                    hintText: 'key1: value1, key2: value2',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _generate,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('生成合同'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ]),
            ),
    );
  }
}
