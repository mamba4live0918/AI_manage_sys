import 'package:flutter/material.dart';
import 'hr_approval_tab.dart';

class HrApprovalPage extends StatelessWidget {
  const HrApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('审批管理')),
      body: const HrApprovalTab(),
    );
  }
}
