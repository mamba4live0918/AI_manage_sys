import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_client.dart';
import '../../config/theme.dart';

final _statusLabels = {
  'scheduled': '待面试',
  'completed': '已完成',
  'cancelled': '已取消',
};

final _statusColors = {
  'scheduled': AppTheme.blue,
  'completed': AppTheme.green,
  'cancelled': Colors.grey,
};

class HrInterviewTab extends StatefulWidget {
  const HrInterviewTab({super.key});

  @override
  State<HrInterviewTab> createState() => _HrInterviewTabState();
}

class _HrInterviewTabState extends State<HrInterviewTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _interviews = [];
  bool _loading = true;
  DateTime _selectedDay = DateTime.now();
  DateTime _displayMonth = DateTime.now();
  bool _monthView = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/hr/interviews', queryParameters: {'limit': 200});
      setState(() {
        _interviews = (resp.data['items'] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    return _interviews.where((i) {
      final at = i['scheduled_at'] as String?;
      if (at == null) return false;
      final d = DateTime.parse(at);
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
  }

  int _eventCountOnDay(DateTime day) {
    return _interviews.where((i) {
      final at = i['scheduled_at'] as String?;
      if (at == null) return false;
      final d = DateTime.parse(at);
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).length;
  }

  List<DateTime> _monthDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final startOffset = firstDay.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final days = <DateTime>[];
    for (int i = startOffset - 1; i >= 0; i--) {
      days.add(firstDay.subtract(Duration(days: i + 1)));
    }
    for (int i = 0; i < daysInMonth; i++) {
      days.add(DateTime(month.year, month.month, i + 1));
    }
    while (days.length < 42) {
      final last = days.last;
      days.add(DateTime(last.year, last.month, last.day + 1));
    }
    return days;
  }

  Future<void> _showForm({Map<String, dynamic>? interview}) async {
    final isEdit = interview != null;
    final nameCtrl = TextEditingController(text: interview?['candidate_name'] ?? '');
    final posCtrl = TextEditingController(text: interview?['position'] ?? '');
    final durCtrl = TextEditingController(text: '${interview?['duration_minutes'] ?? 30}');
    final notesCtrl = TextEditingController(text: interview?['notes'] ?? '');
    String status = interview?['status'] ?? 'scheduled';
    DateTime date;
    TimeOfDay time;

    if (interview?['scheduled_at'] != null) {
      final dt = DateTime.parse(interview!['scheduled_at']);
      date = dt;
      time = TimeOfDay.fromDateTime(dt);
    } else {
      date = _selectedDay;
      time = const TimeOfDay(hour: 10, minute: 0);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(isEdit ? '编辑面试' : '新建面试'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '候选人姓名')),
              const SizedBox(height: 12),
              TextField(controller: posCtrl, decoration: const InputDecoration(labelText: '职位')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('日期', style: TextStyle(fontSize: 14)),
                    subtitle: Text(DateFormat('yyyy-MM-dd').format(date)),
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (picked != null) setDlg(() => date = picked);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('时间', style: TextStyle(fontSize: 14)),
                    subtitle: Text(time.format(ctx)),
                    onTap: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: time);
                      if (picked != null) setDlg(() => time = picked);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: durCtrl, decoration: const InputDecoration(labelText: '时长(分钟)', suffixText: '分钟'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: '备注'), maxLines: 3),
              if (isEdit) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状态'),
                  items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setDlg(() => status = v!),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final scheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                final body = {
                  'candidate_name': nameCtrl.text.trim(),
                  'position': posCtrl.text.trim(),
                  'scheduled_at': scheduled.toIso8601String(),
                  'duration_minutes': int.tryParse(durCtrl.text.trim()) ?? 30,
                  'notes': notesCtrl.text.trim(),
                  if (isEdit) 'status': status,
                };
                try {
                  if (isEdit) {
                    await _api.dio.put('/hr/interviews/${interview['id']}', data: body);
                  } else {
                    await _api.dio.post('/hr/interviews', data: body);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (_) {}
              },
              child: Text(isEdit ? '保存' : '创建'),
            ),
          ],
        ),
      ),
    );
    if (result == true) _load();
  }

  Future<void> _updateStatus(Map<String, dynamic> i, String newStatus) async {
    final scheduled = DateTime.parse(i['scheduled_at'] as String);
    try {
      await _api.dio.put('/hr/interviews/${i['id']}', data: {
        'candidate_name': i['candidate_name'],
        'position': i['position'],
        'scheduled_at': scheduled.toIso8601String(),
        'duration_minutes': i['duration_minutes'] ?? 30,
        'notes': i['notes'] ?? '',
        'status': newStatus,
      });
      _load();
    } catch (_) {}
  }

  Future<void> _deleteInterview(Map<String, dynamic> i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除面试'),
        content: Text('确定删除「${i['candidate_name']}」的面试吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除'), style: FilledButton.styleFrom(backgroundColor: Colors.red)),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/hr/interviews/${i['id']}');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _eventsForDay(_selectedDay);
    final monthDays = _monthDays(_displayMonth);
    final weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];
    final today = DateTime.now();

    return Column(children: [
      // Month nav + view toggle
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          if (_monthView) ...[
            IconButton(icon: const Icon(Icons.chevron_left_rounded, size: 20), onPressed: () => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1, 1)), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
            Text(DateFormat('yyyy年M月').format(_displayMonth), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            IconButton(icon: const Icon(Icons.chevron_right_rounded, size: 20), onPressed: () => setState(() => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1, 1)), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
          ] else ...[
            IconButton(icon: const Icon(Icons.chevron_left_rounded, size: 20), onPressed: () => setState(() => _selectedDay = DateTime(_selectedDay.year, _selectedDay.month - 1, _selectedDay.day.clamp(1, 28))), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
            Text(DateFormat('yyyy年M月').format(_selectedDay), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            IconButton(icon: const Icon(Icons.chevron_right_rounded, size: 20), onPressed: () => setState(() => _selectedDay = DateTime(_selectedDay.year, _selectedDay.month + 1, _selectedDay.day.clamp(1, 28))), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
          ],
          const Spacer(),
          Text('${_selectedDay.month}/${_selectedDay.day} (${events.length})', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(width: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('月', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: false, label: Text('周', style: TextStyle(fontSize: 11))),
            ],
            selected: {_monthView},
            onSelectionChanged: (v) => setState(() => _monthView = v.first),
            style: ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ]),
      ),
      // Calendar
      if (_monthView)
        LayoutBuilder(
          builder: (ctx, constraints) {
            final cellW = (constraints.maxWidth - 2) / 7;
            return Column(children: [
              // Weekday headers
              Row(
                children: weekdayLabels.map((l) => SizedBox(
                  width: cellW,
                  child: Center(child: Text(l, style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                )).toList(),
              ),
              const SizedBox(height: 2),
              // Day grid using Wrap — no GridView to avoid touch conflict
              Wrap(
                children: monthDays.map((d) {
                  final isCurrentMonth = d.month == _displayMonth.month;
                  final isSelected = d.year == _selectedDay.year && d.month == _selectedDay.month && d.day == _selectedDay.day;
                  final isTodayLocal = d.year == today.year && d.month == today.month && d.day == today.day;
                  final dayEvents = _eventsForDay(d);
                  final count = dayEvents.length;
                  final tooltip = count > 0
                      ? dayEvents.map((e) => '${e['candidate_name']} (${DateFormat('HH:mm').format(DateTime.parse(e['scheduled_at']))})').join('\n')
                      : null;

                  Widget cell = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _selectedDay = d;
                      if (d.month != _displayMonth.month) _displayMonth = DateTime(d.year, d.month, 1);
                    }),
                    child: Container(
                      width: cellW,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.blue : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: isTodayLocal && !isSelected ? Border.all(color: AppTheme.blue, width: 1.5) : null,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text('${d.day}', style: TextStyle(
                            fontSize: 12,
                            fontWeight: isTodayLocal || isSelected ? FontWeight.w600 : FontWeight.w400,
                            color: isSelected ? Colors.white : isCurrentMonth ? null : Colors.grey.shade400,
                          )),
                          if (count > 0 && isCurrentMonth)
                            Positioned(
                              bottom: 1,
                              child: Text('$count', style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : Colors.orange,
                              )),
                            ),
                        ],
                      ),
                    ),
                  );

                  if (tooltip != null) {
                    cell = Tooltip(message: tooltip, child: cell);
                  }
                  return cell;
                }).toList(),
              ),
            ]);
          },
        )
      else
        // Week strip — compact horizontal date picker
        SizedBox(
          height: 68,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: 31,
            itemBuilder: (_, i) {
              final d = DateTime(_selectedDay.year, _selectedDay.month, i + 1);
              final isSelected = d.day == _selectedDay.day;
              final dayEvents = _eventsForDay(d);
              final count = dayEvents.length;
              final tooltip = count > 0
                  ? dayEvents.map((e) => '${e['candidate_name']} (${DateFormat('HH:mm').format(DateTime.parse(e['scheduled_at']))})').join('\n')
                  : null;

              Widget cell = GestureDetector(
                onTap: () => setState(() => _selectedDay = d),
                child: Container(
                  width: 48,
                  margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.blue : null,
                    borderRadius: BorderRadius.circular(10),
                    border: !isSelected ? Border.all(color: Colors.grey.withAlpha(40)) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(DateFormat('E').format(d).substring(0, 1), style: TextStyle(fontSize: 10, color: isSelected ? Colors.white70 : Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    Text('${d.day}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : null)),
                    if (count > 0) Text('$count场', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.orange)),
                  ]),
                ),
              );

              if (tooltip != null) {
                cell = Tooltip(message: tooltip, child: cell);
              }
              return cell;
            },
          ),
        ),
      // Event list
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : events.isEmpty
                ? Center(child: Text('当日无面试安排', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: events.length,
                    itemBuilder: (_, i) {
                      final e = events[i];
                      final status = e['status'] as String? ?? 'scheduled';
                      final statusColor = _statusColors[status] ?? Colors.grey;
                      final scheduledAt = e['scheduled_at'] as String?;
                      final timeStr = scheduledAt != null ? DateFormat('HH:mm').format(DateTime.parse(scheduledAt)) : '未安排';
                      final dur = e['duration_minutes'] as int? ?? 30;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(width: 4, height: 40, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2))),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(e['candidate_name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text('${e['position'] ?? ''}  ·  $timeStr  ·  ${dur}分钟', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                ]),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: statusColor.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                                child: Text(_statusLabels[status] ?? status, style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500)),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              if (status == 'scheduled') ...[
                                _QuickButton(
                                  icon: Icons.check_circle_outline_rounded,
                                  label: '完成面试',
                                  color: AppTheme.green,
                                  onTap: () => _updateStatus(e, 'completed'),
                                ),
                                const SizedBox(width: 8),
                                _QuickButton(
                                  icon: Icons.cancel_outlined,
                                  label: '取消面试',
                                  color: Colors.orange,
                                  onTap: () => _updateStatus(e, 'cancelled'),
                                ),
                              ] else ...[
                                _QuickButton(
                                  icon: Icons.refresh_rounded,
                                  label: '恢复待面',
                                  color: AppTheme.blue,
                                  onTap: () => _updateStatus(e, 'scheduled'),
                                ),
                              ],
                              const SizedBox(width: 8),
                              _QuickButton(
                                icon: Icons.delete_outline_rounded,
                                label: '删除',
                                color: Colors.red,
                                onTap: () => _deleteInterview(e),
                              ),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
