import 'package:flutter/material.dart';
import 'hr_approval_tab.dart';

class HrApprovalPage extends StatelessWidget {
  final VoidCallback? onBack;
  const HrApprovalPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('审批管理'),
        leading: onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack) : null,
      ),
      body: const HrApprovalTab(),
    );
  }
}
