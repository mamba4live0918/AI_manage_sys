import 'package:flutter/material.dart';
import 'finance_voucher_tab.dart';

class FinanceVoucherPage extends StatelessWidget {
  final VoidCallback? onBack;
  const FinanceVoucherPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('凭证管理'),
        leading: onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack)
            : null,
      ),
      body: const FinanceVoucherTab(),
    );
  }
}
