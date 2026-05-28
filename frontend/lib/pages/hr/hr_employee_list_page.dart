import 'package:flutter/material.dart';
import 'hr_user_management_tab.dart';

class HrEmployeeListPage extends StatelessWidget {
  const HrEmployeeListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('员工管理')),
      body: const HrUserManagementTab(),
    );
  }
}
