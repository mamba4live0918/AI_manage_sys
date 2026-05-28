import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import 'pm_project_list_tab.dart';
import 'pm_project_detail_page.dart';
import 'pm_visit_log_tab.dart';
import 'pm_courseware_tab.dart';
import 'pm_overview_tab.dart';

class PmDashboardPage extends ConsumerStatefulWidget {
  const PmDashboardPage({super.key});

  @override
  ConsumerState<PmDashboardPage> createState() => _PmDashboardPageState();
}

class _PmDashboardPageState extends ConsumerState<PmDashboardPage>
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
          title: const Text('项目管理'),
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabs: const [
              Tab(text: '概览'),
              Tab(text: '项目'),
              Tab(text: '走访日志'),
              Tab(text: '课件'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            const PmOverviewTab(),
            PmProjectListTab(onProjectSelected: (id) {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => PmProjectDetailPage(projectId: id),
              ));
            }),
            const PmVisitLogTab(),
            const PmCoursewareTab(),
          ],
        ),
      ),
    );
  }
}
