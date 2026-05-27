import 'package:flutter/material.dart';
import '../../services/api_client.dart';

class MarketingChurnConfigPage extends StatefulWidget {
  final Map<String, dynamic>? churnConfig;
  const MarketingChurnConfigPage({super.key, this.churnConfig});

  @override
  State<MarketingChurnConfigPage> createState() => _MarketingChurnConfigPageState();
}

class _MarketingChurnConfigPageState extends State<MarketingChurnConfigPage> {
  final _api = ApiClient();
  late int _inactivityDays;
  late int _lowThreshold;
  late bool _autoNotify;

  @override
  void initState() {
    super.initState();
    _inactivityDays = widget.churnConfig?['inactivity_days'] as int? ?? 90;
    _lowThreshold = widget.churnConfig?['low_satisfaction_threshold'] as int? ?? 40;
    _autoNotify = widget.churnConfig?['auto_notify'] as bool? ?? true;
  }

  Future<void> _save() async {
    await _api.dio.put('/marketing/churn-config', data: {
      'inactivity_days': _inactivityDays,
      'low_satisfaction_threshold': _lowThreshold,
      'auto_notify': _autoNotify,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('流失预警配置')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SwitchListTile(
          title: const Text('自动通知'),
          subtitle: Text(_autoNotify ? '开启' : '关闭'),
          value: _autoNotify,
          onChanged: (v) => setState(() => _autoNotify = v),
        ),
        ListTile(
          title: const Text('不活跃天数阈值'),
          subtitle: Text('$_inactivityDays 天'),
          trailing: SizedBox(
            width: 100,
            child: TextField(
              controller: TextEditingController(text: '$_inactivityDays'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _inactivityDays = int.tryParse(v) ?? 90,
              decoration: const InputDecoration(isDense: true, suffixText: '天'),
            ),
          ),
        ),
        ListTile(
          title: const Text('低满意度阈值'),
          subtitle: Text('$_lowThreshold 分'),
          trailing: SizedBox(
            width: 100,
            child: TextField(
              controller: TextEditingController(text: '$_lowThreshold'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _lowThreshold = int.tryParse(v) ?? 40,
              decoration: const InputDecoration(isDense: true, suffixText: '分'),
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _save, child: const Text('保存配置')),
      ]),
    );
  }
}
