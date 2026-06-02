import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';

const _typeNames = {'leave': '请假', 'expense': '报销', 'regularization': '转正'};
const _statusNames = {'pending': '待审批', 'approved': '已通过', 'rejected': '已驳回'};
const _statusColors = {'pending': Colors.orange, 'approved': Colors.green, 'rejected': Colors.red};

class ApprovalSubmitPage extends ConsumerStatefulWidget {
  const ApprovalSubmitPage({super.key});
  @override
  ConsumerState<ApprovalSubmitPage> createState() => _ApprovalSubmitPageState();
}

class _ApprovalSubmitPageState extends ConsumerState<ApprovalSubmitPage> with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  final _contentCtrl = TextEditingController();
  String _type = 'leave';
  bool _submitting = false;
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _history = [];
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() { if (!_tabCtrl.indexIsChanging && _tabCtrl.index == 1) _loadHistory(); });
  }

  @override
  void dispose() {
    _contentCtrl.dispose(); _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (_loadingHistory) return;
    setState(() => _loadingHistory = true);
    try {
      final resp = await _api.dio.get('/hr/approvals', queryParameters: {'limit': '100'});
      setState(() => _history = List<Map<String, dynamic>>.from(resp.data['items']));
    } catch (_) {}
    setState(() => _loadingHistory = false);
  }

  Future<void> _submit() async {
    if (_contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写申报说明'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _submitting = true);
    try {
      await _api.dio.post('/hr/approvals', data: {'approval_type': _type, 'content': _contentCtrl.text.trim()});
      if (mounted) {
        setState(() { _submitting = false; _contentCtrl.clear(); _type = 'leave'; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('提交成功，等待审批'), backgroundColor: AppTheme.green));
        _tabCtrl.animateTo(1);
        _loadHistory();
      }
    } catch (e) {
      if (mounted) { setState(() => _submitting = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败: $e'), backgroundColor: Colors.red)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('发起审批'), bottom: TabBar(controller: _tabCtrl, tabs: const [Tab(text: '提交'), Tab(text: '我的记录')])),
      body: TabBarView(controller: _tabCtrl, children: [
        _buildSubmitForm(user),
        _buildHistory(isDark),
      ]),
    );
  }

  Widget _buildSubmitForm(dynamic user) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                if (user != null)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.business, size: 16, color: AppTheme.accent), const SizedBox(width: 8), Text('${user.department} · ${user.username}', style: const TextStyle(fontSize: 14, color: AppTheme.accent))])),
                const SizedBox(height: 20),
                InputDecorator(decoration: const InputDecoration(labelText: '审批类型'),
                  child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _type, isExpanded: true, isDense: true, items: _typeNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 15)))).toList(), onChanged: (v) => setState(() => _type = v!)))),
                const SizedBox(height: 16),
                TextField(controller: _contentCtrl, maxLines: 4, minLines: 3, decoration: const InputDecoration(labelText: '申报说明', hintText: '请详细描述您要申请的事项...', border: OutlineInputBorder())),
                const SizedBox(height: 24),
                SizedBox(height: 48, child: FilledButton.icon(icon: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded), label: Text(_submitting ? '提交中...' : '提交申请'), onPressed: _submitting ? null : _submit)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(bool isDark) {
    if (_loadingHistory) return const Center(child: CircularProgressIndicator());
    if (_history.isEmpty) return Center(child: Text('暂无审批记录', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45)));

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _history.length,
        itemBuilder: (_, i) {
          final a = _history[i];
          final status = a['status'] ?? 'pending';
          final sc = _statusColors[status] ?? Colors.grey;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid, border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null, boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 1))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: sc)),
                const SizedBox(width: 8),
                Text(_typeNames[a['approval_type']] ?? a['approval_type'], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: sc.withAlpha(isDark ? 25 : 18)),
                  child: Text(_statusNames[status] ?? status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sc))),
              ]),
              const SizedBox(height: 6),
              Text(a['content'] ?? '', style: TextStyle(fontSize: 14, color: isDark ? AppTheme.darkText : AppTheme.lightText), maxLines: 3, overflow: TextOverflow.ellipsis),
              if ((a['comment'] as String?)?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 4), child: Text('审批意见: ${a['comment']}', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
            ]),
          );
        },
      ),
    );
  }
}
