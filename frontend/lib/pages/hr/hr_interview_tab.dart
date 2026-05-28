import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
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

class HrInterviewTab extends ConsumerStatefulWidget {
  const HrInterviewTab({super.key});

  @override
  ConsumerState<HrInterviewTab> createState() => _HrInterviewTabState();
}

class _HrInterviewTabState extends ConsumerState<HrInterviewTab> {
  List<Map<String, dynamic>> _interviews = [];
  bool _loading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient().dio.get('/hr/interviews', queryParameters: {'limit': '200'});
      final items = (resp.data['items'] as List).cast<Map<String, dynamic>>();
      setState(() { _interviews = items; _loading = false; });
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

  Future<void> _showForm({Map<String, dynamic>? interview}) async {
    final isEdit = interview != null;
    final nameCtrl = TextEditingController(text: interview?['candidate_name'] ?? '');
    final posCtrl = TextEditingController(text: interview?['position'] ?? '');
    final durCtrl = TextEditingController(text: '${interview?['duration_minutes'] ?? 30}');
    final notesCtrl = TextEditingController(text: interview?['notes'] ?? '');
    final statusCtrl = TextEditingController(text: interview?['status'] ?? 'scheduled');
    var date = interview?['scheduled_at'] != null
        ? DateTime.parse(interview!['scheduled_at'])
        : DateTime.now().add(const Duration(hours: 1));
    var time = TimeOfDay.fromDateTime(date);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(isEdit ? '编辑面试' : '新建面试'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '候选人姓名')),
                const SizedBox(height: 12),
                TextField(controller: posCtrl, decoration: const InputDecoration(labelText: '职位')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('日期', style: TextStyle(fontSize: 14)),
                        subtitle: Text(DateFormat('yyyy-MM-dd').format(date)),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2030),
                          );
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
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: durCtrl, decoration: const InputDecoration(labelText: '时长(分钟)', suffixText: '分钟'), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: '备注'), maxLines: 3),
                if (isEdit) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: statusCtrl.text,
                    decoration: const InputDecoration(labelText: '状态'),
                    items: _statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setDlg(() { statusCtrl.text = v!; }),
                  ),
                ],
              ],
            ),
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
                  if (isEdit) 'status': statusCtrl.text,
                };
                try {
                  if (isEdit) {
                    await ApiClient().dio.put('/hr/interviews/${interview!['id']}', data: body);
                  } else {
                    await ApiClient().dio.post('/hr/interviews', data: body);
                  }
                  Navigator.pop(ctx, true);
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
      await ApiClient().dio.delete('/hr/interviews/${i['id']}');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final events = _eventsForDay(_selectedDay);

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              // Calendar
              TableCalendar(
                firstDay: DateTime(2020),
                lastDay: DateTime(2030),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: CalendarFormat.month,
                onDaySelected: (selected, focused) => setState(() { _selectedDay = selected; _focusedDay = focused; }),
                onPageChanged: (focused) => setState(() => _focusedDay = focused),
                eventLoader: _eventsForDay,
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    if (events.isEmpty) return null;
                    return Positioned(
                      bottom: 1,
                      child: Container(
                        width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: _statusColors[(events.first as Map<String, dynamic>)['status'] as String? ?? 'scheduled'] ?? Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(color: AppTheme.blue.withAlpha(40), shape: BoxShape.circle),
                  selectedDecoration: const BoxDecoration(color: AppTheme.blue, shape: BoxShape.circle),
                ),
                headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              ),
              const Divider(height: 1),
              // Selected day events
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '${_selectedDay.month}/${_selectedDay.day} 面试 (${events.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建'),
                      onPressed: () => _showForm(),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: events.isEmpty
                    ? Center(
                        child: Text('当日无面试安排', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                      )
                    : ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (context, idx) => _InterviewCard(
                          interview: events[idx],
                          onTap: () => _showForm(interview: events[idx]),
                          onDelete: () => _deleteInterview(events[idx]),
                        ),
                      ),
              ),
            ],
          );
  }
}

class _InterviewCard extends StatelessWidget {
  final Map<String, dynamic> interview;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _InterviewCard({required this.interview, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = interview['status'] as String? ?? 'scheduled';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final scheduledAt = interview['scheduled_at'] as String?;
    final timeStr = scheduledAt != null
        ? DateFormat('HH:mm').format(DateTime.parse(scheduledAt))
        : '未安排';
    final dur = interview['duration_minutes'] as int? ?? 30;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: (isDark ? Colors.white : Colors.black).withAlpha(6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 4, height: 40,
                decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(interview['candidate_name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${interview['position'] ?? ''}  ·  $timeStr  ·  ${dur}分钟',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _statusLabels[status] ?? status,
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                color: Colors.red.shade300,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
