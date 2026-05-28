import 'package:flutter/material.dart';
import 'hr_resume_tab.dart';

class HrResumePage extends StatelessWidget {
  const HrResumePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('简历管理')),
      body: const HrResumeTab(),
    );
  }
}
