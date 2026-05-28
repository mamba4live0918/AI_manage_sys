import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../preview/preview_page.dart';

const _statusNames = {'new': '新简历', 'reviewing': '评估中', 'reviewed': '已评估'};

class _RadarPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final double maxVal;

  _RadarPainter(this.labels, this.values, this.maxVal);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 30;
    final n = labels.length;
    if (n < 3) return;

    final paint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final fillPaint = Paint()
      ..color = AppTheme.blue.withAlpha(40)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = AppTheme.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final dotPaint = Paint()
      ..color = AppTheme.blue
      ..style = PaintingStyle.fill;

    for (int level = 1; level <= 5; level++) {
      final path = Path();
      final r = radius * level / 5;
      for (int i = 0; i < n; i++) {
        final angle = -math.pi / 2 + 2 * math.pi * i / n;
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    final axisPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      canvas.drawLine(center, Offset(center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle)), axisPaint);
    }

    final dataPath = Path();
    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final ratio = values[i] / maxVal;
      final r = radius * ratio;
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      points.add(Offset(x, y));
      if (i == 0) {
        dataPath.moveTo(x, y);
      } else {
        dataPath.lineTo(x, y);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, strokePaint);
    for (final p in points) {
      canvas.drawCircle(p, 3, dotPaint);
    }

    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      final labelRadius = radius + 18;
      final x = center.dx + labelRadius * math.cos(angle);
      final y = center.dy + labelRadius * math.sin(angle);
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: const TextStyle(fontSize: 10, color: Colors.black87)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    final avgScore = values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
    final scoreTp = TextPainter(
      text: TextSpan(
        text: avgScore.toStringAsFixed(1),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.blue),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    scoreTp.paint(canvas, Offset(center.dx - scoreTp.width / 2, center.dy - scoreTp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}

class HrResumeTab extends StatefulWidget {
  const HrResumeTab({super.key});

  @override
  State<HrResumeTab> createState() => _HrResumeTabState();
}

class _HrResumeTabState extends State<HrResumeTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _resumes = [];
  List<Map<String, dynamic>> _interviews = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.dio.get('/hr/resumes', queryParameters: {'limit': 50}),
        _api.dio.get('/hr/interviews', queryParameters: {'limit': 200}),
      ]);
      setState(() {
        _resumes = List<Map<String, dynamic>>.from(results[0].data['items']);
        _interviews = List<Map<String, dynamic>>.from(results[1].data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _findInterview(String candidateName) {
    for (final iv in _interviews) {
      if ((iv['candidate_name'] as String? ?? '') == candidateName) return iv;
    }
    return null;
  }

  Future<void> _upload() async {
    final nameCtrl = TextEditingController();

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final bytes = picked.path != null ? await File(picked.path!).readAsBytes() : picked.bytes;
    if (bytes == null) return;

    nameCtrl.text = picked.name.replaceAll(RegExp(r'\.[^.]+$'), '');

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传简历'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.insert_drive_file_rounded, size: 20, color: AppTheme.orange),
              const SizedBox(width: 8),
              Expanded(child: Text(picked.name, overflow: TextOverflow.ellipsis)),
              Text('${(picked.size / 1024).toStringAsFixed(0)} KB', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '候选人姓名')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('上传')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: picked.name),
        'name': nameCtrl.text.trim(),
      });
      await _api.dio.post('/hr/resumes/upload', data: formData);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('简历上传成功')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    }
  }

  Future<void> _analyze(String id, String candidateName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final resp = await _api.dio.post('/hr/resumes/$id/match');
      if (mounted) Navigator.pop(context);
      final analysis = resp.data['analysis'] as Map<String, dynamic>?;
      if (analysis == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分析结果解析失败')));
        _load();
        return;
      }
      if (mounted) _showAnalysisDialog(candidateName, analysis);
      _load();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分析失败: $e')));
      }
    }
  }

  Future<void> _scheduleInterview(String candidateName, {Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?['candidate_name'] ?? candidateName);
    final posCtrl = TextEditingController(text: existing?['position'] ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');
    DateTime date;
    TimeOfDay time;

    if (existing?['scheduled_at'] != null) {
      final dt = DateTime.parse(existing!['scheduled_at'] as String);
      date = dt;
      time = TimeOfDay.fromDateTime(dt);
    } else {
      date = DateTime.now().add(const Duration(days: 1));
      time = const TimeOfDay(hour: 10, minute: 0);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(isEdit ? '修改面试' : '安排面试'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '候选人姓名')),
              const SizedBox(height: 8),
              TextField(controller: posCtrl, decoration: const InputDecoration(labelText: '面试职位')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('日期', style: TextStyle(fontSize: 13)),
                    subtitle: Text('${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
                    onTap: () async {
                      final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime.now(), lastDate: DateTime(2030));
                      if (picked != null) setDlg(() => date = picked);
                    },
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('时间', style: TextStyle(fontSize: 13)),
                    subtitle: Text('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'),
                    onTap: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: time);
                      if (picked != null) setDlg(() => time = picked);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, maxLines: 2, decoration: const InputDecoration(labelText: '备注')),
            ]),
          ),
          actions: [
            if (isEdit)
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.red),
                onPressed: () async {
                  await _api.dio.delete('/hr/interviews/${existing['id']}');
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('取消面试'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('关闭')),
            FilledButton(
              onPressed: () async {
                final newScheduled = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                if (isEdit) {
                  await _api.dio.put('/hr/interviews/${existing['id']}', data: {
                    'candidate_name': nameCtrl.text.trim(),
                    'position': posCtrl.text.trim(),
                    'scheduled_at': newScheduled.toIso8601String(),
                    'notes': notesCtrl.text.trim(),
                  });
                } else {
                  await _api.dio.post('/hr/interviews', data: {
                    'candidate_name': nameCtrl.text.trim(),
                    'position': posCtrl.text.trim(),
                    'scheduled_at': newScheduled.toIso8601String(),
                    'notes': notesCtrl.text.trim(),
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text(isEdit ? '保存' : '安排'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? '面试已更新' : '面试已安排')));
      _load();
    }
  }

  void _showAnalysisDialog(String candidateName, Map<String, dynamic> analysis) {
    final scores = (analysis['scores'] as Map<String, dynamic>?) ?? {};
    final strengths = analysis['strengths'] as String? ?? '';
    final departmentMatches = (analysis['department_matches'] as List?) ?? [];
    final recommendedSalary = analysis['recommended_salary'] as String? ?? '';
    final summary = analysis['summary'] as String? ?? '';

    final labels = scores.keys.toList();
    final values = scores.values.map((v) => (v as num).toDouble()).toList();
    final maxVal = values.isEmpty ? 10.0 : values.reduce(math.max);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$candidateName 能力评估', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (values.length >= 3)
                Center(
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: CustomPaint(
                      painter: _RadarPainter(labels, values, maxVal),
                    ),
                  ),
                ),
              if (strengths.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('核心优势', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(strengths, style: const TextStyle(fontSize: 13)),
              ],
              if (departmentMatches.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('部门匹配', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                ...departmentMatches.map((dm) {
                  final d = dm as Map<String, dynamic>;
                  final ds = (d['score'] as num? ?? 0).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Expanded(child: Text(d['department'] ?? '', style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ds / 100,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              ds >= 70 ? AppTheme.green : AppTheme.orange,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${ds.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }),
              ],
              if (recommendedSalary.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('薪资建议', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.green.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(recommendedSalary, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.green)),
                ),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('综合评价', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(summary, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ]),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: const Text('安排面试'),
            onPressed: () {
              Navigator.pop(ctx);
              _scheduleInterview(candidateName);
            },
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除简历'),
        content: Text('确定要删除"$name"的简历吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: AppTheme.red))),
        ],
      ),
    );
    if (ok == true) {
      await _api.dio.delete('/hr/resumes/$id');
      _load();
    }
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(height: 40, child: ElevatedButton.icon(
          onPressed: _upload,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('上传简历 (PDF/DOC/DOCX)'),
        )),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _resumes.isEmpty
                ? Center(child: Text('暂无简历', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _resumes.length,
                    itemBuilder: (_, i) {
                      final r = _resumes[i];
                      final id = r['id'] as String;
                      final name = r['name'] as String? ?? '';
                      final fileId = r['file_id'] as String?;
                      final score = r['match_score'] as num? ?? 0;
                      final status = r['status'] as String? ?? 'new';
                      final isAnalyzed = status == 'reviewed';

                      final interview = _findInterview(name);
                      final hasInterview = interview != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: fileId != null ? const Color(0xFFFFF3E0) : const Color(0xFFF3E8FF),
                                  child: Icon(
                                    fileId != null ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                                    color: fileId != null ? AppTheme.orange : AppTheme.purple,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        if (hasInterview) ...[
                                          const SizedBox(width: 8),
                                          Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.green),
                                          const SizedBox(width: 2),
                                          Text('已约面', style: TextStyle(fontSize: 11, color: AppTheme.green, fontWeight: FontWeight.w500)),
                                        ],
                                      ]),
                                      const SizedBox(height: 2),
                                      Row(children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(4),
                                            color: isAnalyzed ? AppTheme.green.withAlpha(20) : Colors.grey.shade200,
                                          ),
                                          child: Text(
                                            '${_statusNames[status] ?? status}${isAnalyzed ? ' · ${score.toStringAsFixed(0)}分' : ''}',
                                            style: TextStyle(fontSize: 11, color: isAnalyzed ? AppTheme.green : Colors.grey.shade600),
                                          ),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ),
                              ]),
                              if (hasInterview) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.green.withAlpha(15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.green.withAlpha(50)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.event_rounded, size: 13, color: AppTheme.green),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        '面试: ${_formatDateTime(interview['scheduled_at'] as String?)}',
                                        style: TextStyle(fontSize: 11, color: AppTheme.green, fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ]),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (fileId != null) ...[
                                    _actionChip(Icons.visibility_rounded, '查看简历', () {
                                      Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => PreviewPage(fileId: fileId),
                                      ));
                                    }),
                                    const SizedBox(width: 6),
                                  ],
                                  if (hasInterview)
                                    _actionChip(Icons.edit_calendar_rounded, '修改面试', () => _scheduleInterview(name, existing: interview))
                                  else
                                    _actionChip(Icons.calendar_today_rounded, '安排面试', () => _scheduleInterview(name)),
                                  const SizedBox(width: 6),
                                  _actionChip(Icons.auto_awesome_rounded, isAnalyzed ? '重新分析' : 'AI分析', () => _analyze(id, name)),
                                  const Spacer(),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    onSelected: (action) {
                                      if (action == 'delete') _delete(id, name);
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppTheme.blue),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.blue)),
        ]),
      ),
    );
  }
}
