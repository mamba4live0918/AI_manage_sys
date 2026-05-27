import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import 'marketing_customer_list_tab.dart';
import 'marketing_customer_detail_page.dart';
import 'marketing_proposal_tab.dart';
import 'marketing_project_timeline_tab.dart';
import 'marketing_community_dashboard.dart';
import 'marketing_knowledge_manage_page.dart';

class MarketingDashboardPage extends ConsumerStatefulWidget {
  const MarketingDashboardPage({super.key});

  @override
  ConsumerState<MarketingDashboardPage> createState() => _MarketingDashboardPageState();
}

class _MarketingDashboardPageState extends ConsumerState<MarketingDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
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
          title: const Text('市场部'),
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabs: const [
              Tab(text: '客户管理'),
              Tab(text: '方案生成'),
              Tab(text: '项目跟进'),
              Tab(text: '社群运营'),
              Tab(text: '知识库'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            MarketingCustomerListTab(onCustomerSelected: (id) {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => MarketingCustomerDetailPage(customerId: id),
              ));
            }),
            const MarketingProposalTab(),
            const MarketingProjectTimelineTab(),
            const MarketingCommunityDashboard(),
            const MarketingKnowledgeManagePage(),
          ],
        ),
      ),
    );
  }
}
