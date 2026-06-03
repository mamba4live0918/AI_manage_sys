import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../preview/preview_page.dart';

class _ChatMessage {
  final String role;
  final String content;
  final String? model;
  final List<Map<String, dynamic>>? sources;
  final DateTime timestamp;

  _ChatMessage({required this.role, required this.content, this.model, this.sources, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toHistory() => {'role': role, 'content': content};
}

class MarketingKnowledgeQAPage extends StatefulWidget {
  final String qaEndpoint;
  final String title;
  final String? historyEndpoint;
  const MarketingKnowledgeQAPage({super.key, this.qaEndpoint = '/marketing/knowledge/qa', this.title = '知识库问答', this.historyEndpoint});

  @override
  State<MarketingKnowledgeQAPage> createState() => _MarketingKnowledgeQAPageState();

  static Future<void> show(BuildContext context, {
    String qaEndpoint = '/marketing/knowledge/qa',
    String title = '知识库问答',
    String? historyEndpoint,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'QA',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim1, anim2) => MarketingKnowledgeQAPage(
        qaEndpoint: qaEndpoint,
        title: title,
        historyEndpoint: historyEndpoint,
      ),
    );
  }
}

class _MarketingKnowledgeQAPageState extends State<MarketingKnowledgeQAPage> {
  final _api = ApiClient();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _loading = false;
  bool _historyOpen = false;
  List<Map<String, dynamic>> _historyItems = [];
  bool _historyLoading = false;
  String? _historyError;
  String _mode = 'flexible'; // 'precise' | 'flexible'

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _loadHistory() async {
    if (widget.historyEndpoint == null) return;
    setState(() { _historyLoading = true; _historyError = null; });
    try {
      final resp = await _api.dio.get(widget.historyEndpoint!);
      setState(() {
        _historyItems = List<Map<String, dynamic>>.from(resp.data['items'] as List? ?? []);
        _historyLoading = false;
      });
    } catch (e) {
      setState(() { _historyError = e.toString(); _historyLoading = false; });
    }
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    _textCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final history = _messages.length > 1
          ? _messages.sublist(0, _messages.length - 1).map((m) => m.toHistory()).toList()
          : <Map<String, dynamic>>[];

      final resp = await _api.dio.post(widget.qaEndpoint, data: {
        'question': text,
        'mode': _mode,
        'history': history.length > 20 ? history.sublist(history.length - 20) : history,
      });

      final answer = resp.data['answer'] as String? ?? '';
      final model = resp.data['model'] as String?;
      final sourcesRaw = resp.data['sources'] as List<dynamic>?;
      final sources = sourcesRaw?.map((s) => Map<String, dynamic>.from(s as Map)).toList();

      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: answer, model: model, sources: sources));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', content: '抱歉，请求失败：$e'));
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  void _newChat() {
    setState(() => _messages.clear());
  }

  void _openHistoryItem(Map<String, dynamic> item) {
    final q = item['question'] as String? ?? '';
    final a = item['answer'] as String? ?? '';
    final src = item['sources'] as List<dynamic>?;
    final model = item['model'] as String?;
    final sources = src?.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    setState(() {
      _messages.clear();
      _messages.add(_ChatMessage(role: 'user', content: q));
      _messages.add(_ChatMessage(role: 'assistant', content: a, model: model, sources: sources));
    });
    _scrollToBottom();
  }

  void _toggleHistory() {
    final open = !_historyOpen;
    setState(() => _historyOpen = open);
    if (open) _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.of(context).size.width * 0.06,
        vertical: MediaQuery.of(context).size.height * 0.06,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 24, spreadRadius: 2)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _historyOpen ? 280 : 36,
            child: _historyOpen ? _buildHistoryPanel(theme) : _buildCollapsedTab(theme),
          ),
          Expanded(child: _buildChatArea(theme)),
        ]),
      ),
    );
  }

  Widget _buildHistoryPanel(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.blue.withAlpha(15) : AppTheme.blue.withAlpha(12),
        border: Border(right: BorderSide(color: isDark ? Colors.white.withAlpha(60) : AppTheme.blue.withAlpha(60), width: 1)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
          child: Row(children: [
            const Icon(Icons.history_rounded, size: 18, color: AppTheme.blue),
            const SizedBox(width: 8),
            Text('对话历史', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              tooltip: '收起',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => setState(() => _historyOpen = false),
            ),
          ]),
        ),
        Expanded(
          child: _historyLoading
              ? const Center(child: CircularProgressIndicator())
              : _historyError != null
                  ? Center(child: Text('加载失败', style: TextStyle(fontSize: 13, color: theme.colorScheme.error)))
                  : _historyItems.isEmpty
                      ? Center(child: Text('暂无对话记录', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(120))))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _historyItems.length,
                          itemBuilder: (_, i) {
                            final item = _historyItems[i];
                            final q = item['question'] as String? ?? '';
                            final a = item['answer'] as String? ?? '';
                            final time = item['created_at'] as String? ?? '';
                            final dateStr = time.length >= 10 ? time.substring(0, 10) : time;
                            return InkWell(
                              onTap: () => _openHistoryItem(item),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                                    if (dateStr.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(dateStr, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withAlpha(100))),
                                    ],
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(a, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(140), height: 1.4)),
                                  const SizedBox(height: 6),
                                  Divider(height: 0, color: theme.dividerColor.withAlpha(30)),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }

  Widget _buildCollapsedTab(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: _toggleHistory,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.blue.withAlpha(15) : AppTheme.blue.withAlpha(12),
          border: Border(
            right: BorderSide(color: isDark ? Colors.white.withAlpha(80) : AppTheme.blue.withAlpha(100), width: 1.5),
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chevron_right_rounded, size: 22, color: AppTheme.blue),
            const SizedBox(height: 6),
            RotatedBox(
              quarterTurns: -1,
              child: Text('历史', style: TextStyle(fontSize: 11, color: AppTheme.blue, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildChatArea(ThemeData theme) {
    return Column(children: [
      _buildHeader(theme),
      // Mode toggle
      _buildModeToggle(theme),
      Expanded(
        child: _messages.isEmpty && !_loading
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_rounded, size: 48, color: AppTheme.blue.withAlpha(80)),
                  const SizedBox(height: 8),
                  Text('基于知识库内容的智能问答', style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withAlpha(150))),
                ]),
              )
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _messages.length + (_loading ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _messages.length) return _buildTypingBubble(theme);
                  return _buildMessageBubble(_messages[i], theme);
                },
              ),
      ),
      _buildInputBar(theme),
    ]);
  }

  Widget _buildModeToggle(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        _modeChip('precise', '精准', Icons.precision_manufacturing_rounded, isDark),
        const SizedBox(width: 8),
        _modeChip('flexible', '灵活', Icons.lightbulb_rounded, isDark),
      ]),
    );
  }

  Widget _modeChip(String mode, String label, IconData icon, bool isDark) {
    final active = _mode == mode;
    return Material(
      color: active ? AppTheme.blue.withAlpha(25) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _mode = mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: active ? AppTheme.blue : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? AppTheme.blue : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary))),
            if (active) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_rounded, size: 14, color: AppTheme.blue),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        Expanded(
          child: Text(widget.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
        ),
        if (_messages.isNotEmpty)
          TextButton.icon(
            onPressed: _newChat,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('新建', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ]),
    );
  }

  Widget _buildTypingBubble(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
        Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: const BorderRadius.only(topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.blue.withAlpha(150)),
            ),
            const SizedBox(width: 10),
            Text('AI 正在思考...', style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(150))),
          ]),
        ),
      ]),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg, ThemeData theme) {
    final isUser = msg.role == 'user';
    final bubbleColor = isUser ? AppTheme.blue : theme.colorScheme.surfaceContainerHighest;
    final textColor = isUser ? Colors.white : theme.colorScheme.onSurface;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: isUser ? const Radius.circular(18) : Radius.zero,
      bottomRight: isUser ? Radius.zero : const Radius.circular(18),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.blue.withAlpha(30),
                child: const Icon(Icons.smart_toy_rounded, size: 16, color: AppTheme.blue),
              ),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.55),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.amber.withAlpha(40),
                        ),
                        child: const Text('AI 生成', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.w600)),
                      ),
                      if (msg.model != null && msg.model!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: AppTheme.blue.withAlpha(15),
                          ),
                          child: Text(msg.model!, style: const TextStyle(fontSize: 10, color: AppTheme.blue)),
                        ),
                      ],
                    ]),
                  ),
                SelectableText(msg.content, style: TextStyle(fontSize: 14, height: 1.7, color: textColor)),
                if (!isUser && msg.sources != null && msg.sources!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ExpansionTileSource(sources: msg.sources!),
                ],
                if (!isUser) ...[
                  const SizedBox(height: 8),
                  Text('以上内容由 AI 生成，仅供参考',
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withAlpha(80), fontStyle: FontStyle.italic)),
                ],
              ]),
            ),
          ),
          if (isUser)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.blue.withAlpha(180),
                child: const Icon(Icons.person_rounded, size: 16, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4, offset: const Offset(0, -1))],
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _textCtrl,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            enabled: !_loading,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: '输入问题...（Enter 发送）',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 40, height: 40,
          child: IconButton.filled(
            onPressed: _loading ? null : _send,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded, size: 18),
            style: IconButton.styleFrom(backgroundColor: AppTheme.blue),
          ),
        ),
      ]),
    );
  }
}

class ExpansionTileSource extends StatefulWidget {
  final List<Map<String, dynamic>> sources;
  const ExpansionTileSource({super.key, required this.sources});

  @override
  State<ExpansionTileSource> createState() => _ExpansionTileSourceState();
}

class _ExpansionTileSourceState extends State<ExpansionTileSource> {
  bool _expanded = false;

  void _handleFileTap(String sourceFileId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PreviewPage(fileId: sourceFileId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: AppTheme.blue.withAlpha(180)),
          const SizedBox(width: 2),
          Text('参考来源 (${widget.sources.length})', style: const TextStyle(fontSize: 12, color: AppTheme.blue, fontWeight: FontWeight.w600)),
        ]),
      ),
      if (_expanded) ...[
        const SizedBox(height: 6),
        ...widget.sources.asMap().entries.map((e) {
          final i = e.key + 1;
          final s = e.value;
          final sourceFileId = s['source_file_id'] as String?;
          final hasFile = sourceFileId != null && sourceFileId.isNotEmpty;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppTheme.blue.withAlpha(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: AppTheme.blue.withAlpha(30)),
                  child: Text('[$i]', style: const TextStyle(fontSize: 10, color: AppTheme.blue, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(s['title'] as String? ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                if (hasFile)
                  InkWell(
                    onTap: () => _handleFileTap(sourceFileId!),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: AppTheme.blue.withAlpha(20),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.insert_drive_file_rounded, size: 12, color: AppTheme.blue),
                        SizedBox(width: 2),
                        Text('查看文件', style: TextStyle(fontSize: 10, color: AppTheme.blue, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
              ]),
              if ((s['content_preview'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(s['content_preview'] as String? ?? '', maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withAlpha(150))),
              ],
            ]),
          );
        }),
      ],
    ]);
  }
}
