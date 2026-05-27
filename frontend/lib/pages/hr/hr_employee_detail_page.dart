import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class HrEmployeeDetailPage extends StatefulWidget {
  final String employeeId;
  const HrEmployeeDetailPage({super.key, required this.employeeId});

  @override
  State<HrEmployeeDetailPage> createState() => _HrEmployeeDetailPageState();
}

class _HrEmployeeDetailPageState extends State<HrEmployeeDetailPage> {
  final _api = ApiClient();
  Map<String, dynamic>? _employee;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/hr/employees/${widget.employeeId}');
      setState(() { _employee = resp.data; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const statusNames = {'active': '在职', 'resigned': '离职', 'probation': '试用期'};

    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('员工详情')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_employee == null) {
      return Scaffold(appBar: AppBar(title: const Text('员工详情')), body: const Center(child: Text('加载失败')));
    }

    final e = _employee!;
    final status = e['status'] as String? ?? 'active';

    return Scaffold(
      appBar: AppBar(title: Text(e['name'] as String? ?? '员工详情')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: AppTheme.green.withAlpha(20)),
              child: Text(statusNames[status] ?? status, style: const TextStyle(fontSize: 12, color: AppTheme.green)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.grey.withAlpha(15)),
              child: Text(e['position'] as String? ?? '', style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 24),
          _infoRow('电话', e['phone'] as String? ?? ''),
          _infoRow('邮箱', e['email'] as String? ?? ''),
          _infoRow('入职日期', (e['hire_date'] as String? ?? '').substring(0, 10)),
          if ((e['notes'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('备注', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SelectableText(e['notes'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.8)),
          ],
        ]),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withAlpha(150)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
      ]),
    );
  }
}
