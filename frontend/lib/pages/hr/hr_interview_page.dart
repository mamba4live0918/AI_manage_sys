import 'package:flutter/material.dart';
import 'hr_interview_tab.dart';

class HrInterviewPage extends StatelessWidget {
  const HrInterviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('面试安排')),
      body: const HrInterviewTab(),
    );
  }
}
