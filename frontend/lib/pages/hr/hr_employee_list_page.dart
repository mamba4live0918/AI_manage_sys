import 'package:flutter/material.dart';
import 'hr_user_management_tab.dart';

class HrEmployeeListPage extends StatelessWidget {
  final VoidCallback? onBack;
  const HrEmployeeListPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('员工管理'),
        leading: onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack) : null,
      ),
      body: const HrUserManagementTab(),
    );
  }
}
