import 'package:flutter/material.dart';
import 'finance_settlement_tab.dart';

class FinanceSettlementPage extends StatelessWidget {
  final VoidCallback? onBack;
  const FinanceSettlementPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('结算管理'),
        leading: onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack)
            : null,
      ),
      body: const FinanceSettlementTab(),
    );
  }
}
