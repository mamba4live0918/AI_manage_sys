import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class MarketingCommunityDashboard extends StatefulWidget {
  const MarketingCommunityDashboard({super.key});

  @override
  State<MarketingCommunityDashboard> createState() => _MarketingCommunityDashboardState();
}

class _MarketingCommunityDashboardState extends State<MarketingCommunityDashboard> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _interactions = [];
  List<Map<String, dynamic>> _activity = [];
  List<Map<String, dynamic>> _hotTopics = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final interactions = await _api.dio.get('/marketing/community/interactions', queryParameters: {'limit': 50});
      final activity = await _api.dio.get('/marketing/community/activity', queryParameters: {'days': 30});
      final topics = await _api.dio.get('/marketing/community/hot-topics');
      setState(() {
        _interactions = List<Map<String, dynamic>>.from(interactions.data['items']);
        _activity = List<Map<String, dynamic>>.from(activity.data['items']);
        _hotTopics = List<Map<String, dynamic>>.from(topics.data['topics']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _addInteraction() async {
    final contentCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String platform = 'wechat_group';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('记录社群互动'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InputDecorator(
                decoration: const InputDecoration(labelText: '平台'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: platform, isExpanded: true, isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'wechat_group', child: Text('微信群')),
                      DropdownMenuItem(value: 'wechat_channel', child: Text('微信公众号')),
                      DropdownMenuItem(value: 'xiaohongshu', child: Text('小红书')),
                      DropdownMenuItem(value: 'douyin', child: Text('抖音')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) => setDlg(() => platform = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '用户名')),
              const SizedBox(height: 8),
              TextField(controller: contentCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '互动内容 *')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存并分析')),
          ],
        ),
      ),
    );
    if (ok != true || contentCtrl.text.trim().isEmpty) return;

    await _api.dio.post('/marketing/community/interactions', data: {
      'platform': platform,
      'user_name': nameCtrl.text.trim(),
      'content': contentCtrl.text.trim(),
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sentimentLabels = {'positive': '正面', 'neutral': '中性', 'negative': '负面'};
    final sentimentColors = {'positive': Colors.green, 'neutral': Colors.grey, 'negative': Colors.red};

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Activity chart — simple bar chart
              if (_activity.isNotEmpty) ...[
                const Text('社群活跃度', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: _activity.take(14).map((a) {
                          final active = (a['active_users'] as int?) ?? 0;
                          final maxActive = _activity.map((x) => (x['active_users'] as int?) ?? 0).reduce((a, b) => a > b ? a : b);
                          final h = maxActive > 0 ? (active / maxActive * 100).toDouble() : 0.0;
                          final date = (a['date'] as String? ?? '').substring(5);
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 1),
                              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                Text(active > 0 ? '$active' : '', style: const TextStyle(fontSize: 9, color: AppTheme.purple)),
                                const SizedBox(height: 2),
                                Container(
                                  height: h + 1,
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                    color: AppTheme.purple.withAlpha(180),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(date, style: const TextStyle(fontSize: 8)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Hot topics
              if (_hotTopics.isNotEmpty) ...[
                const Text('热门话题', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _hotTopics.take(12).map((t) {
                    final count = t['count'] as int? ?? 0;
                    final opacity = count > 20 ? 60 : count > 10 ? 40 : 20;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: AppTheme.purple.withAlpha(opacity),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(t['tag'] as String? ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.purple)),
                        const SizedBox(width: 4),
                        Text('$count', style: TextStyle(fontSize: 10, color: AppTheme.purple.withAlpha(150))),
                      ]),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              // Interactions list
              Row(children: [
                const Text('社群互动', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: _addInteraction,
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('记录互动', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (_interactions.isEmpty)
                Center(child: Text('暂无互动', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
              else
                ..._interactions.map((interaction) {
                  final sentiment = interaction['sentiment'] as String? ?? 'neutral';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (sentimentColors[sentiment] ?? Colors.grey).withAlpha(30),
                        radius: 16,
                        child: Icon(
                          sentiment == 'positive' ? Icons.sentiment_satisfied_rounded : sentiment == 'negative' ? Icons.sentiment_dissatisfied_rounded : Icons.sentiment_neutral_rounded,
                          size: 16,
                          color: sentimentColors[sentiment] ?? Colors.grey,
                        ),
                      ),
                      title: Row(children: [
                        Expanded(child: Text(interaction['user_name'] as String? ?? '匿名', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: (sentimentColors[sentiment] ?? Colors.grey).withAlpha(20),
                          ),
                          child: Text(sentimentLabels[sentiment] ?? sentiment, style: TextStyle(fontSize: 10, color: sentimentColors[sentiment] ?? Colors.grey)),
                        ),
                      ]),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(interaction['content'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        if ((interaction['tags'] as List<dynamic>?)?.isNotEmpty == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(spacing: 4, children: (interaction['tags'] as List<dynamic>).map((t) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: AppTheme.purple.withAlpha(15)),
                              child: Text(t.toString(), style: const TextStyle(fontSize: 10, color: AppTheme.purple)),
                            )).toList()),
                          ),
                      ]),
                      trailing: Text(interaction['interaction_date']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(120))),
                    ),
                  );
                }),
            ]),
          );
  }
}
