import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

const _categoryNames = {
  'travel': '差旅', 'office': '办公', 'entertainment': '招待',
  'equipment': '设备', 'salary': '工资', 'training': '培训',
  'marketing': '市场', 'other': '其他',
};

class ExpenseSubmitPage extends ConsumerStatefulWidget {
  const ExpenseSubmitPage({super.key});

  @override
  ConsumerState<ExpenseSubmitPage> createState() => _ExpenseSubmitPageState();
}

class _ExpenseSubmitPageState extends ConsumerState<ExpenseSubmitPage> {
  final _api = ApiClient();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'other';
  String _expenseType = 'reimbursement';
  PlatformFile? _pickedFile;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = '请输入有效的金额');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final data = <String, dynamic>{
        'amount': amount,
        'category': _category,
        'expense_type': _expenseType,
        'description': _descCtrl.text.trim(),
      };

      final resp = await _api.dio.post('/finance/expenses', data: data);
      final expenseId = resp.data['id'] as String;

      final file = _pickedFile;
      if (file != null && file.bytes != null) {
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes!, filename: file.name),
          'type': 'receipt',
          'description': _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : file.name,
          'expense_id': expenseId,
        });
        await _api.dio.post('/finance/vouchers/upload', data: formData);
      }

      if (mounted) {
        setState(() {
          _submitting = false;
          _amountCtrl.clear();
          _descCtrl.clear();
          _category = 'other';
          _pickedFile = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('提交成功，等待财务审批'), backgroundColor: AppTheme.green),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.watch(authProvider);
    final user = auth.user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('支出报销')),
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
                    // Department badge
                    if (user != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.business, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('${user.department}', style: const TextStyle(fontSize: 14, color: Colors.blue)),
                        ]),
                      ),
                    const SizedBox(height: 20),

                    // Amount
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefix: const Text('\u{FFE5} ', style: TextStyle(fontSize: 20)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Category
                    InputDecorator(
                      decoration: const InputDecoration(labelText: '费用类别'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _category, isExpanded: true, isDense: true,
                          items: _categoryNames.entries
                              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                              .toList(),
                          onChanged: (v) => setState(() => _category = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    TextField(
                      controller: _descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: '说明', hintText: '简单描述用途'),
                    ),
                    const SizedBox(height: 16),

                    // File upload
                    OutlinedButton.icon(
                      icon: Icon(_pickedFile != null ? Icons.check_circle : Icons.attach_file,
                          color: _pickedFile != null ? AppTheme.green : null),
                      label: Text(_pickedFile?.name ?? '上传凭证（可选）'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: _pickedFile != null ? AppTheme.green : Colors.grey.shade400),
                      ),
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          withData: true, allowMultiple: false,
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png'],
                        );
                        if (result != null && result.files.isNotEmpty) {
                          setState(() => _pickedFile = result.files.first);
                        }
                      },
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Submit
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        icon: _submitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded),
                        label: Text(_submitting ? '提交中...' : '提交报销'),
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
