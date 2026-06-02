import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';

class PmVisitLogTab extends StatefulWidget {
  final String? projectId;
  const PmVisitLogTab({super.key, this.projectId});

  @override
  State<PmVisitLogTab> createState() => _PmVisitLogTabState();
}

class _PmVisitLogTabState extends State<PmVisitLogTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _selectedProjectId = widget.projectId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final projects = await _api.dio.get('/pm/projects', queryParameters: {'limit': 100});
      setState(() {
        _projects = List<Map<String, dynamic>>.from(projects.data['items']);
      });
      if (_selectedProjectId != null) {
        final logs = await _api.dio.get('/pm/projects/$_selectedProjectId/logs', queryParameters: {'limit': 50});
        setState(() { _logs = List<Map<String, dynamic>>.from(logs.data['items']); });
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final contentCtrl = TextEditingController();
    final locationCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建走访日志'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: '地点')),
            const SizedBox(height: 8),
            TextField(controller: contentCtrl, maxLines: 4, decoration: const InputDecoration(labelText: '内容')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true || _selectedProjectId == null) return;

    await _api.dio.post('/pm/projects/$_selectedProjectId/logs', data: {
      'content': contentCtrl.text.trim(),
      'location': locationCtrl.text.trim(),
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

  Widget _buildVisitCard(Map<String, dynamic> l, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppTheme.blue)),
          const SizedBox(width: 8),
          Text('走访日志', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          const Spacer(),
          Text((l['visited_at'] as String? ?? '').length >= 10 ? (l['visited_at'] as String).substring(0, 10) : '', style: TextStyle(fontSize: 11, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: AppTheme.blue.withAlpha(isDark ? 25 : 18)),
            child: const Icon(Icons.location_on_rounded, color: AppTheme.blue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l['location'] as String? ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkText : AppTheme.lightText), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(l['content'] as String? ?? '', style: TextStyle(fontSize: 12, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ]),
    );
  }

    return Column(children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final dropdown = Expanded(
            child: InputDecorator(
              decoration: const InputDecoration(labelText: '项目', contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedProjectId,
                  isExpanded: true, isDense: true,
                  hint: const Text('选择项目'),
                  items: _projects.map((p) => DropdownMenuItem(
                    value: p['id'] as String?,
                    child: Text(p['name'] as String? ?? '', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) { _selectedProjectId = v; _load(); },
                ),
              ),
            ),
          );
          final addBtn = SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _selectedProjectId != null ? _create : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新增'),
            ),
          );
          if (constraints.maxWidth < 600) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                dropdown,
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: addBtn),
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              dropdown,
              const SizedBox(width: 8),
              addBtn,
            ]),
          );
        },
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _selectedProjectId == null
                ? Center(child: Text('请选择一个项目', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : _logs.isEmpty
                    ? Center(child: Text('暂无走访日志', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                    : LayoutBuilder(
                        builder: (ctx, constraints) {
                          final w = constraints.maxWidth;
                          final cols = w >= 500 ? 2 : 1;
                          final cardWidth = (w - 12 * (cols + 1)) / cols;
                          return SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final l in _logs)
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildVisitCard(l, isDark),
                                ),
                            ]),
                          );
                        },
                      ),
      ),
    ]);
  }
}
