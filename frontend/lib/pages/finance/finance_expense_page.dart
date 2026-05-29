import 'package:flutter/material.dart';
import 'finance_expense_tab.dart';

class FinanceExpensePage extends StatelessWidget {
  final VoidCallback? onBack;
  const FinanceExpensePage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('报销管理'),
        leading: onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack)
            : null,
      ),
      body: const FinanceExpenseTab(),
    );
  }
}
