import 'package:flutter/material.dart';
import 'hr_resume_tab.dart';

class HrResumePage extends StatelessWidget {
  final VoidCallback? onBack;
  const HrResumePage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('简历管理'),
        leading: onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack) : null,
      ),
      body: const HrResumeTab(),
    );
  }
}
