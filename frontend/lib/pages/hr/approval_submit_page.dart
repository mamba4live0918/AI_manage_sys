import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

const _typeNames = {'leave': '请假', 'expense': '报销', 'regularization': '转正'};

class ApprovalSubmitPage extends ConsumerStatefulWidget {
  const ApprovalSubmitPage({super.key});

  @override
  ConsumerState<ApprovalSubmitPage> createState() => _ApprovalSubmitPageState();
}

class _ApprovalSubmitPageState extends ConsumerState<ApprovalSubmitPage> {
  final _api = ApiClient();
  final _contentCtrl = TextEditingController();
  String _type = 'leave';
  bool _submitting = false;

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_contentCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await _api.dio.post('/hr/approvals', data: {
        'approval_type': _type,
        'content': _contentCtrl.text.trim(),
      });
      if (mounted) {
        setState(() { _submitting = false; _contentCtrl.clear(); _type = 'leave'; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提交成功，等待审批'), backgroundColor: AppTheme.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('发起审批')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (user != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.business, size: 16, color: AppTheme.accent),
                          const SizedBox(width: 8),
                          Text('${user.department}  ·  ${user.username}',
                              style: const TextStyle(fontSize: 14, color: AppTheme.accent)),
                        ]),
                      ),
                    const SizedBox(height: 20),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: '审批类型'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _type, isExpanded: true, isDense: true,
                          items: _typeNames.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => setState(() => _type = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _contentCtrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: '申请内容',
                        hintText: '详细描述申请理由...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        icon: _submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded),
                        label: Text(_submitting ? '提交中...' : '提交审批'),
                        onPressed: _submitting ? null : _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
