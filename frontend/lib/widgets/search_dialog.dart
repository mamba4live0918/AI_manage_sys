import 'package:flutter/material.dart';
import '../services/api_client.dart';

final _moduleLabels = {
  'bidding_knowledge': '招投标知识库',
  'marketing_knowledge': '市场知识库',
  'customers': '客户',
  'proposals': '营销方案',
  'contracts': '合同',
  'projects': '项目',
  'coursewares': '课件',
  'employees': '员工',
  'resumes': '简历',
};

final _moduleIcons = {
  'bidding_knowledge': Icons.gavel_rounded,
  'marketing_knowledge': Icons.campaign_rounded,
  'customers': Icons.person_rounded,
  'proposals': Icons.description_rounded,
  'contracts': Icons.article_rounded,
  'projects': Icons.engineering_rounded,
  'coursewares': Icons.school_rounded,
  'employees': Icons.people_rounded,
  'resumes': Icons.badge_rounded,
};

class SearchDialog extends StatefulWidget {
  const SearchDialog({super.key});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _results = [];
  int _total = 0;
  int _tookMs = 0;
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _results = []; _total = 0; _tookMs = 0; });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final resp = await ApiClient().dio.get('/search', queryParameters: {'q': query, 'size': '50'});
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _results = List<Map<String, dynamic>>.from(data['items'] ?? []);
        _total = data['total'] ?? 0;
        _tookMs = data['took_ms'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '搜索失败，请稍后重试';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '搜索知识库、客户、合同、项目...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _controller.clear();
                                  _search('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: (isDark ? Colors.white : Colors.black).withAlpha(8),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 15),
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      onChanged: (v) {
                        if (v.isEmpty) _search('');
                        setState(() {}); // toggle clear button
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
            // results
            Flexible(
              child: _buildBody(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(_error, style: TextStyle(color: Colors.red.shade300)),
            ],
          ),
        ),
      );
    }
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('输入关键词开始搜索', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('未找到相关结果', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
          child: Text(
            '共 $_total 条结果（${_tookMs}ms）',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _results.length,
            itemBuilder: (context, i) => _ResultCard(item: _results[i], isDark: isDark),
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isDark;

  const _ResultCard({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final module = item['module'] as String? ?? '';
    final title = item['title'] as String? ?? '';
    final content = item['content'] as String? ?? '';
    final score = (item['score'] as num?)?.toDouble() ?? 0.0;
    final label = _moduleLabels[module] ?? module;
    final icon = _moduleIcons[module] ?? Icons.search_rounded;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      elevation: 0,
      color: (isDark ? Colors.white : Colors.black).withAlpha(6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: score > 2 ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                content.length > 200 ? '${content.substring(0, 200)}...' : content,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
