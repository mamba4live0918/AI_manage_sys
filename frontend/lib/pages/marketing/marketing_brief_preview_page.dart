import 'package:flutter/material.dart';
import '../../config/theme.dart';

class MarketingBriefPreviewPage extends StatefulWidget {
  final String projectName;
  final String content;
  final String html;
  final String model;
  const MarketingBriefPreviewPage({
    super.key,
    required this.projectName,
    required this.content,
    required this.html,
    required this.model,
  });

  @override
  State<MarketingBriefPreviewPage> createState() => MarketingBriefPreviewPageState();
}

class MarketingBriefPreviewPageState extends State<MarketingBriefPreviewPage> {
  bool _showHtml = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.model.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppTheme.purple.withAlpha(20)),
                child: Text(widget.model, style: const TextStyle(fontSize: 12, color: AppTheme.purple)),
              ),
            ),
          if (widget.html.isNotEmpty)
            SizedBox(
              height: 34,
              child: ToggleButtons(
                isSelected: [!_showHtml, _showHtml],
                onPressed: (i) => setState(() => _showHtml = i == 1),
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 30),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                selectedColor: Colors.white,
                fillColor: AppTheme.purple,
                color: AppTheme.purple.withAlpha(150),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Markdown')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('HTML')),
                ],
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _showHtml && widget.html.isNotEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(widget.html, style: const TextStyle(fontSize: 13)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: SelectableText(widget.content, style: const TextStyle(fontSize: 15, height: 1.8)),
            ),
    );
  }
}
