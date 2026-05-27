import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import 'marketing_churn_config_page.dart';
import 'marketing_demand_prediction_page.dart';

const _eventTypeNames = {
  'meeting': '会议', 'call': '电话', 'email': '邮件', 'purchase': '采购',
  'complaint': '投诉', 'inquiry': '咨询', 'visit': '拜访', 'other': '其他',
};

class MarketingCustomerDetailPage extends StatefulWidget {
  final String customerId;
  const MarketingCustomerDetailPage({super.key, required this.customerId});

  @override
  State<MarketingCustomerDetailPage> createState() => _MarketingCustomerDetailPageState();
}

class _MarketingCustomerDetailPageState extends State<MarketingCustomerDetailPage>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  late final TabController _tabCtrl;
  Map<String, dynamic>? _customer;
  List<Map<String, dynamic>> _behaviors = [];
  List<Map<String, dynamic>> _satisfactions = [];
  List<Map<String, dynamic>> _trend = [];
  Map<String, dynamic>? _churnConfig;
  List<Map<String, dynamic>> _warnings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this)..addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        if (_tabCtrl.index == 1) _loadBehaviors();
        if (_tabCtrl.index == 2) _loadSatisfactions();
        if (_tabCtrl.index == 3) _loadChurn();
      }
    });
    _loadCustomer();
    _loadBehaviors();
    _loadSatisfactions();
    _loadChurn();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomer() async {
    try {
      final resp = await _api.dio.get('/marketing/customers/${widget.customerId}');
      setState(() { _customer = Map<String, dynamic>.from(resp.data); _loading = false; });
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _loadBehaviors() async {
    try {
      final resp = await _api.dio.get('/marketing/customers/${widget.customerId}/behaviors', queryParameters: {'limit': 50});
      setState(() { _behaviors = List<Map<String, dynamic>>.from(resp.data['items']); });
    } catch (_) {}
  }

  Future<void> _addBehavior() async {
    String eventType = 'meeting';
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('记录事件'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            InputDecorator(
              decoration: const InputDecoration(labelText: '事件类型'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: eventType, isExpanded: true, isDense: true,
                  items: _eventTypeNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setDlg(() => eventType = v!),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '描述')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _api.dio.post('/marketing/customers/${widget.customerId}/behaviors', data: {
      'event_type': eventType, 'description': descCtrl.text,
    });
    _loadBehaviors();
  }

  Future<void> _loadSatisfactions() async {
    try {
      final sat = await _api.dio.get('/marketing/customers/${widget.customerId}/satisfactions', queryParameters: {'limit': 50});
      final trend = await _api.dio.get('/marketing/customers/${widget.customerId}/satisfaction-trend');
      setState(() {
        _satisfactions = List<Map<String, dynamic>>.from(sat.data['items']);
        _trend = List<Map<String, dynamic>>.from(trend.data['trend']);
      });
    } catch (_) {}
  }

  Future<void> _addSatisfaction() async {
    final scoreCtrl = TextEditingController(text: '80');
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('记录满意度'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: scoreCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '评分 (1-100)')),
          const SizedBox(height: 8),
          TextField(controller: commentCtrl, decoration: const InputDecoration(labelText: '备注')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    await _api.dio.post('/marketing/customers/${widget.customerId}/satisfactions', data: {
      'score': int.tryParse(scoreCtrl.text) ?? 80, 'comment': commentCtrl.text,
    });
    _loadSatisfactions();
  }

  Future<void> _loadChurn() async {
    try {
      final config = await _api.dio.get('/marketing/churn-config');
      final warnings = await _api.dio.get('/marketing/churn-warnings',
        queryParameters: {'customer_id': widget.customerId, 'limit': 20});
      setState(() {
        _churnConfig = Map<String, dynamic>.from(config.data);
        _warnings = List<Map<String, dynamic>>.from(warnings.data['items']);
      });
    } catch (_) {}
  }

  Future<void> _checkChurn() async {
    try {
      await _api.dio.post('/marketing/customers/${widget.customerId}/check-churn');
      _loadChurn();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('流失检查完成')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('检查失败: $e')));
    }
  }

  Future<void> _predictDemand() async {
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MarketingDemandPredictionPage(customerId: widget.customerId),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(body: Center(child: Text('加载失败: $_error')));

    final c = _customer!;
    return Scaffold(
      appBar: AppBar(
        title: Text(c['name'] as String? ?? '客户详情'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabs: const [
            Tab(text: '基本信息'),
            Tab(text: '行为时间轴'),
            Tab(text: '满意度'),
            Tab(text: '流失预警'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildInfoTab(theme, c),
          _buildBehaviorTab(theme),
          _buildSatisfactionTab(theme),
          _buildChurnTab(theme),
        ],
      ),
    );
  }

  Widget _buildInfoTab(ThemeData theme, Map<String, dynamic> c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _infoCard(theme, '基本信息', [
          ('行业', c['industry'] ?? ''), ('联系人', c['contact_person'] ?? ''),
          ('联系电话', c['contact_phone'] ?? ''), ('邮箱', c['contact_email'] ?? ''),
          ('来源', _sourceNames[c['source']] ?? c['source'] ?? ''),
          ('状态', _statusNames[c['status']] ?? c['status'] ?? ''),
        ]),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 44, child: FilledButton.icon(
          onPressed: _predictDemand,
          icon: const Icon(Icons.psychology_rounded, size: 20),
          label: const Text('AI 需求预测', style: TextStyle(fontSize: 15)),
        )),
      ]),
    );
  }

  Widget _buildBehaviorTab(ThemeData theme) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(
          onPressed: _addBehavior,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('记录事件'),
        )),
      ),
      Expanded(
        child: _behaviors.isEmpty
            ? Center(child: Text('暂无行为记录', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _behaviors.length,
                itemBuilder: (_, i) {
                  final b = _behaviors[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.purple.withAlpha(20),
                        radius: 16,
                        child: Text(_eventTypeNames[b['event_type']]?[0] ?? '?', style: const TextStyle(fontSize: 12, color: AppTheme.purple)),
                      ),
                      title: Text(_eventTypeNames[b['event_type']] ?? b['event_type'] ?? '', style: const TextStyle(fontSize: 14)),
                      subtitle: Text(b['description'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Text(b['event_date']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(120))),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildSatisfactionTab(ThemeData theme) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(width: double.infinity, height: 40, child: ElevatedButton.icon(
          onPressed: _addSatisfaction,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('记录评分'),
        )),
      ),
      if (_trend.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _trend.map((t) {
                final score = (t['avg_score'] as num?)?.toDouble() ?? 0;
                final h = (score / 100) * 100;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text(score.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
                      const SizedBox(height: 2),
                      Container(height: h, decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        color: score >= 70 ? Colors.green : score >= 40 ? Colors.orange : Colors.red,
                      )),
                      const SizedBox(height: 4),
                      Text(t['month']?.toString() ?? '', style: const TextStyle(fontSize: 9)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      Expanded(
        child: _satisfactions.isEmpty
            ? Center(child: Text('暂无评分记录', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _satisfactions.length,
                itemBuilder: (_, i) {
                  final s = _satisfactions[i];
                  return ListTile(
                    title: Text('评分: ${s['score']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(s['comment'] as String? ?? ''),
                    trailing: Text(s['survey_date']?.toString().substring(0, 10) ?? ''),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildChurnTab(ThemeData theme) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: SizedBox(height: 40, child: ElevatedButton.icon(
              onPressed: _checkChurn,
              icon: const Icon(Icons.warning_amber_rounded, size: 18),
              label: const Text('流失检查'),
            )),
          ),
          const SizedBox(width: 8),
          SizedBox(height: 40, child: OutlinedButton(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => MarketingChurnConfigPage(churnConfig: _churnConfig),
              ));
              _loadChurn();
            },
            child: const Text('配置'),
          )),
        ]),
      ),
      Expanded(
        child: _warnings.isEmpty
            ? Center(child: Text('暂无预警', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _warnings.length,
                itemBuilder: (_, i) {
                  final w = _warnings[i];
                  final riskColors = {'low': Colors.green, 'medium': Colors.orange, 'high': Colors.red, 'critical': Colors.deepPurple};
                  final riskLabels = {'low': '低', 'medium': '中', 'high': '高', 'critical': '严重'};
                  final risk = w['risk_level'] as String? ?? 'medium';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (riskColors[risk] ?? Colors.orange).withAlpha(30),
                        radius: 16,
                        child: Icon(Icons.warning_rounded, size: 16, color: riskColors[risk] ?? Colors.orange),
                      ),
                      title: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: (riskColors[risk] ?? Colors.orange).withAlpha(30),
                          ),
                          child: Text(riskLabels[risk] ?? risk, style: TextStyle(fontSize: 11, color: riskColors[risk] ?? Colors.orange)),
                        ),
                        const SizedBox(width: 8),
                        Text(w['resolved'] == true ? '已解决' : '未解决', style: TextStyle(fontSize: 12, color: w['resolved'] == true ? Colors.green : Colors.red)),
                      ]),
                      subtitle: Text(w['reason'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _infoCard(ThemeData theme, String title, List<(String, String)> fields) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...fields.where((f) => f.$2.isNotEmpty).map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 80, child: Text(f.$1, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(120)))),
              Expanded(child: Text(f.$2, style: const TextStyle(fontSize: 13))),
            ]),
          )),
        ]),
      ),
    );
  }
}

const _sourceNames = {
  'referral': '客户推荐', 'website': '网站', 'exhibition': '展会',
  'cold_call': '电话陌拜', 'other': '其他',
};
const _statusNames = {'active': '活跃', 'dormant': '休眠', 'churned': '已流失'};


