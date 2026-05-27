import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../preview/preview_page.dart';

const _statusNames = {'new': '新简历', 'reviewing': '评估中', 'reviewed': '已评估'};

class HrResumeTab extends StatefulWidget {
  const HrResumeTab({super.key});

  @override
  State<HrResumeTab> createState() => _HrResumeTabState();
}

class _HrResumeTabState extends State<HrResumeTab> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _resumes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get('/hr/resumes', queryParameters: {'limit': 50});
      setState(() {
        _resumes = List<Map<String, dynamic>>.from(resp.data['items']);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final nameCtrl = TextEditingController();

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null) return;

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
        'file': MultipartFile.fromBytes(picked.bytes!, filename: picked.name),
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

  Future<void> _match(String id) async {
    try {
      final resp = await _api.dio.post('/hr/resumes/$id/match');
      _load();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('匹配结果'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('综合评分: ${resp.data['match_score']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 12),
                  SelectableText(resp.data['match_result'] as String? ?? ''),
                ]),
              ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('匹配失败: $e')));
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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: fileId != null ? const Color(0xFFFFF3E0) : const Color(0xFFF3E8FF),
                            child: Icon(
                              fileId != null ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                              color: fileId != null ? AppTheme.orange : AppTheme.purple,
                              size: 20,
                            ),
                          ),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${_statusNames[status] ?? status} · 评分: ${score.toStringAsFixed(0)}',
                            maxLines: 1,
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (fileId != null)
                              IconButton(
                                icon: const Icon(Icons.visibility_rounded, size: 18, color: AppTheme.blue),
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => PreviewPage(fileId: fileId),
                                  ));
                                },
                                tooltip: '预览简历',
                              ),
                            IconButton(
                              icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: AppTheme.orange),
                              onPressed: () => _match(id),
                              tooltip: '智能匹配',
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18),
                              onSelected: (action) {
                                if (action == 'delete') _delete(id, name);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.red))),
                              ],
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}
