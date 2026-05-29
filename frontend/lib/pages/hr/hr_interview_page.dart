import 'package:flutter/material.dart';
import 'hr_interview_tab.dart';

class HrInterviewPage extends StatelessWidget {
  final VoidCallback? onBack;
  const HrInterviewPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('面试安排'),
        leading: onBack != null ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack) : null,
      ),
      body: const HrInterviewTab(),
    );
  }
}
