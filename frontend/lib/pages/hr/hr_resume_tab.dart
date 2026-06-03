import 'dart:convert';
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
  final bool isDark;

  _RadarPainter(this.labels, this.values, this.maxVal, {this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 30;
    final n = labels.length;
    if (n < 3) return;

    final gridColor = isDark ? Colors.white.withAlpha(25) : Colors.grey.shade300;
    final labelColor = isDark ? Colors.white.withAlpha(180) : Colors.black87;
    final centerColor = isDark ? Colors.white : AppTheme.blue;

    final paint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final fillPaint = Paint()
      ..color = AppTheme.blue.withAlpha(isDark ? 50 : 40)
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
      ..color = gridColor
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
        text: TextSpan(text: labels[i], style: TextStyle(fontSize: 10, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }

    final avgScore = values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
    final scoreTp = TextPainter(
      text: TextSpan(
        text: avgScore.toStringAsFixed(1),
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: centerColor),
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
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> get _filteredResumes {
    if (_searchQuery.isEmpty) return _resumes;
    final q = _searchQuery.toLowerCase();
    return _resumes.where((r) {
      final name = (r['name'] as String? ?? '').toLowerCase();
      final status = _statusNames[r['status'] as String?] ?? '';
      return name.contains(q) || status.contains(q);
    }).toList();
  }

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
      builder: (ctx) => _AnalysisDialog(
        resumeId: id,
        candidateName: candidateName,
        api: _api,
        onSchedule: () => _scheduleInterview(candidateName),
        onDone: _load,
      ),
    );
  }

  void _viewAnalysis(String candidateName, String? matchResult) {
    final analysis = _parseMatchResult(matchResult);
    if (analysis == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法解析分析结果')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => _AnalysisDialog(
        candidateName: candidateName,
        analysis: analysis,
        onSchedule: () => _scheduleInterview(candidateName),
      ),
    );
  }

  Map<String, dynamic>? _parseMatchResult(String? matchResult) {
    if (matchResult == null || matchResult.isEmpty) return null;
    try {
      final json = jsonDecode(matchResult);
      if (json is Map<String, dynamic>) return json;
    } catch (_) {}
    // Try markdown code block extraction
    String text = matchResult;
    if (text.startsWith('```')) {
      final lines = text.split('\n');
      if (lines.length > 1) text = lines.skip(1).join('\n');
      final end = text.lastIndexOf('```');
      if (end >= 0) text = text.substring(0, end);
    }
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) return json;
    } catch (_) {}
    return null;
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

  Widget _buildResumeCard(Map<String, dynamic> r, {bool noMargin = false}) {
    final id = r['id'] as String;
    final name = r['name'] as String? ?? '';
    final fileId = r['file_id'] as String?;
    final score = r['match_score'] as num? ?? 0;
    final status = r['status'] as String? ?? 'new';
    final isAnalyzed = status == 'reviewed';

    final interview = _findInterview(name);
    final hasInterview = interview != null;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isAnalyzed ? AppTheme.green : AppTheme.orange;
    return Container(
      margin: noMargin ? null : const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
        border: isDark ? Border.all(color: AppTheme.darkBorder, width: 0.5) : null,
        boxShadow: isDark ? null : const [BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: accentColor)),
          const SizedBox(width: 8),
          Text(isAnalyzed ? '已评估' : '待评估', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          const Spacer(),
          if (hasInterview)
            Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.green),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: (fileId != null ? AppTheme.orange : AppTheme.purple).withAlpha(isDark ? 25 : 18)),
            child: Icon(
              fileId != null ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
              color: fileId != null ? AppTheme.orange : AppTheme.purple,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isDark ? AppTheme.darkText : AppTheme.lightText))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isAnalyzed ? AppTheme.green.withAlpha(isDark ? 25 : 18) : (isDark ? Colors.white12 : Colors.grey.shade200),
                  border: isAnalyzed ? Border.all(color: AppTheme.green.withAlpha(isDark ? 100 : 80)) : null,
                ),
                child: Text(
                  '${_statusNames[status] ?? status}${isAnalyzed ? ' · ${score.toStringAsFixed(0)}分' : ''}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: isAnalyzed ? AppTheme.green : (isDark ? AppTheme.darkTextSecondary : Colors.grey.shade600)),
                ),
              ),
            ]),
            if (hasInterview) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.green.withAlpha(isDark ? 25 : 15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.green.withAlpha(isDark ? 100 : 50)),
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
          ])),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (_, c) {
          final wrapChips = c.maxWidth < 400;
          final chips = <Widget>[
            if (fileId != null)
              _actionChip(Icons.visibility_rounded, '查看简历', () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PreviewPage(fileId: fileId),
                ));
              }),
            if (hasInterview)
              _actionChip(Icons.edit_calendar_rounded, '修改面试', () => _scheduleInterview(name, existing: interview))
            else
              _actionChip(Icons.calendar_today_rounded, '安排面试', () => _scheduleInterview(name)),
            if (isAnalyzed)
              _actionChip(Icons.visibility_rounded, '查看分析', () => _viewAnalysis(name, r['match_result'] as String?)),
            if (isAnalyzed)
              _actionChip(Icons.refresh_rounded, '重新分析', () => _analyze(id, name))
            else
              _actionChip(Icons.auto_awesome_rounded, 'AI分析', () => _analyze(id, name)),
          ];
          if (wrapChips) {
            return Row(children: [
              Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: chips)),
              const SizedBox(width: 4),
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
            ]);
          }
          return Row(children: [
            ...chips.map((c) => Padding(padding: const EdgeInsets.only(right: 6), child: c)),
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
          ]);
        }),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;
    final resumes = _filteredResumes;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '搜索候选人姓名...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear_rounded, size: 18), onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); })
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? AppTheme.darkBorder : Colors.grey.shade300)),
                filled: true,
                fillColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurfaceSolid,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: AppTheme.blue.withAlpha(isDark ? 25 : 18),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _upload,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.upload_file_rounded, size: 18, color: AppTheme.blue),
                  const SizedBox(width: 6),
                  Text('上传简历', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.blue)),
                ]),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : resumes.isEmpty
                ? Center(child: Text(_searchQuery.isEmpty ? '暂无简历' : '无匹配结果', style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(120))))
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      final w = constraints.maxWidth;
                      if (w >= 800) {
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: resumes.length,
                          itemBuilder: (_, i) => _buildResumeCard(resumes[i]),
                        );
                      }
                      final cols = w >= 500 ? 2 : 1;
                      final cardWidth = (w - 12 * (cols + 1)) / cols;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            for (final r in resumes)
                              SizedBox(width: cardWidth, child: _buildResumeCard(r, noMargin: true)),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: AppTheme.blue.withAlpha(isDark ? 20 : 15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: AppTheme.blue),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.blue)),
          ]),
        ),
      ),
    );
  }
}

class _AnalysisDialog extends StatefulWidget {
  final String? resumeId;
  final String candidateName;
  final ApiClient? api;
  final VoidCallback? onSchedule;
  final VoidCallback? onDone;
  final Map<String, dynamic>? analysis;

  const _AnalysisDialog({
    this.resumeId,
    required this.candidateName,
    this.api,
    this.onSchedule,
    this.onDone,
    this.analysis,
  });

  @override
  State<_AnalysisDialog> createState() => _AnalysisDialogState();
}

class _AnalysisDialogState extends State<_AnalysisDialog> {
  bool _loading = true;
  Map<String, dynamic>? _analysisData;
  String? _error;
  final _labels = <String>[];
  final _values = <double>[];
  double _maxVal = 10.0;

  @override
  void initState() {
    super.initState();
    if (widget.analysis != null) {
      _parseAndShow(widget.analysis!);
    } else {
      _callApi();
    }
  }

  void _parseAndShow(Map<String, dynamic> analysis) {
    final scores = (analysis['scores'] as Map<String, dynamic>?) ?? {};
    setState(() {
      _analysisData = analysis;
      _labels.addAll(scores.keys);
      for (final v in scores.values) {
        if (v is Map) {
          _values.add((v['score'] as num?)?.toDouble() ?? 5.0);
        } else {
          _values.add((v as num).toDouble());
        }
      }
      _maxVal = _values.isEmpty ? 10.0 : math.max(_values.reduce(math.max), 1.0);
      _loading = false;
    });
    widget.onDone?.call();
  }

  Future<void> _callApi() async {
    try {
      final resp = await widget.api!.dio.post('/hr/resumes/${widget.resumeId}/match');
      if (!mounted) return;
      final analysis = resp.data['analysis'] as Map<String, dynamic>?;
      if (analysis == null) {
        setState(() { _error = '分析结果解析失败'; _loading = false; });
        return;
      }
      _parseAndShow(analysis);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return AlertDialog(
        title: const Text('分析失败'),
        content: Text(_error!),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext ctx) {
    final a = _analysisData!;
    final scores = (a['scores'] as Map<String, dynamic>?) ?? {};
    final strengths = a['strengths'] as String? ?? '';
    final weaknesses = a['weaknesses'] as String? ?? '';
    final departmentMatches = (a['department_matches'] as List?) ?? [];
    final recommendedSalary = a['recommended_salary'] as String? ?? '';
    final summary = a['summary'] as String? ?? '';
    final overallScore = (a['overall_score'] as num?)?.toDouble();
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final cs = Theme.of(ctx).colorScheme;
    final subtitleColor = cs.onSurface.withAlpha(150);

    return AlertDialog(
      title: Text('${widget.candidateName} 能力评估', style: TextStyle(fontSize: 16, color: cs.onSurface)),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_values.length >= 3)
              Center(
                child: SizedBox(
                  width: 240, height: 240,
                  child: CustomPaint(painter: _RadarPainter(_labels, _values, _maxVal, isDark: isDark)),
                ),
              ),
            if (overallScore != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text('综合评分: ${overallScore.toInt()}分',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
              ),
            ],
            if (scores.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('维度评分', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
              const SizedBox(height: 8),
              ...scores.entries.map((e) {
                final scoreVal = e.value is Map ? (e.value['score'] as num?)?.toDouble() ?? 5.0 : (e.value as num).toDouble();
                final evidence = e.value is Map ? (e.value['evidence'] as String?) ?? '' : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 32, height: 24,
                      child: Center(
                        child: Text('${scoreVal.toInt()}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: scoreVal >= 7 ? AppTheme.green : scoreVal >= 4 ? AppTheme.orange : AppTheme.red)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface)),
                        if (evidence.isNotEmpty)
                          Text(evidence, style: TextStyle(fontSize: 11, color: subtitleColor)),
                      ]),
                    ),
                  ]),
                );
              }),
            ],
            if (strengths.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('核心优势', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.green)),
              const SizedBox(height: 4),
              Text(strengths, style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ],
            if (weaknesses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('风险/短板', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.red)),
              const SizedBox(height: 4),
              Text(weaknesses, style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ],
            if (departmentMatches.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('部门匹配', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
              const SizedBox(height: 4),
              ...departmentMatches.map((dm) {
                final d = dm as Map<String, dynamic>;
                final ds = (d['score'] as num? ?? 0).toDouble();
                final reason = (d['reason'] as String?) ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(d['department'] ?? '', style: TextStyle(fontSize: 13, color: cs.onSurface))),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ds / 100, minHeight: 6,
                            backgroundColor: cs.onSurface.withAlpha(20),
                            valueColor: AlwaysStoppedAnimation<Color>(ds >= 70 ? AppTheme.green : AppTheme.orange),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${ds.toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ]),
                    if (reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 0, top: 2),
                        child: Text(reason, style: TextStyle(fontSize: 11, color: subtitleColor)),
                      ),
                  ]),
                );
              }),
            ],
            if (recommendedSalary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('薪资建议', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.green.withAlpha(isDark ? 30 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(recommendedSalary, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.green)),
              ),
            ],
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('综合评价', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text(summary, style: TextStyle(fontSize: 13, color: subtitleColor)),
            ],
          ]),
        ),
      ),
      actions: [
        if (widget.onSchedule != null)
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: const Text('安排面试'),
            onPressed: () { Navigator.pop(ctx); widget.onSchedule!.call(); },
          ),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
      ],
    );
  }
}
