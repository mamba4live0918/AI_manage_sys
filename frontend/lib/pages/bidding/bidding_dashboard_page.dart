import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/watermark.dart';
import 'bidding_contract_tab.dart';
import 'bidding_knowledge_tab.dart';
import 'bidding_process_tab.dart';
import 'bidding_supplier_tab.dart';

class BiddingDashboardPage extends ConsumerStatefulWidget {
  const BiddingDashboardPage({super.key});

  @override
  ConsumerState<BiddingDashboardPage> createState() => _BiddingDashboardPageState();
}

class _BiddingDashboardPageState extends ConsumerState<BiddingDashboardPage>
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
          title: const Text('招投标'),
          bottom: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabs: const [
              Tab(text: '合同中心'),
              Tab(text: '知识库'),
              Tab(text: '招投标流程'),
              Tab(text: '供应商师资'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: const [
            BiddingContractTab(),
            BiddingKnowledgeTab(),
            BiddingProcessTab(),
            BiddingSupplierTab(),
          ],
        ),
      ),
    );
  }
}
