import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import 'hr_resume_tab.dart';
import 'hr_approval_tab.dart';
import 'hr_interview_tab.dart';
import 'hr_user_management_tab.dart';

class HrDashboardPage extends ConsumerStatefulWidget {
  const HrDashboardPage({super.key});

  @override
  ConsumerState<HrDashboardPage> createState() => _HrDashboardPageState();
}

class _HrDashboardPageState extends ConsumerState<HrDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('HR'),
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabs: const [
              Tab(text: '员工管理'),
              Tab(text: '简历'),
              Tab(text: '审批'),
              Tab(text: '面试'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: const [
            HrUserManagementTab(),
            HrResumeTab(),
            HrApprovalTab(),
            HrInterviewTab(),
          ],
        ),
      ),
    );
  }
}
