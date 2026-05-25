import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_logger.dart';
import '../../widgets/watermark.dart';

class PreviewPage extends ConsumerStatefulWidget {
  final String fileId;
  const PreviewPage({super.key, required this.fileId});

  @override
  ConsumerState<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends ConsumerState<PreviewPage> {
  final _api = ApiClient();
  Map<String, dynamic>? _info;
  WebviewController? _pdfCtrl;
  WebviewController? _avCtrl;
  bool _loading = true;
  String? _error;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _api.dio.get('/preview/file/${widget.fileId}');
      final info = Map<String, dynamic>.from(resp.data);
      final t = info['type'] as String?;
      final mime = info['mime_type'] as String? ?? '';
      _tempPath = info['temp_path'] as String?;
      appLog('[PREVIEW] type=$t mime=$mime');

      if (t == 'media' && mime == 'application/pdf') {
        final pdfUrl = info['url'] as String;
        _pdfCtrl = WebviewController();
        await _pdfCtrl!.initialize();
        await _pdfCtrl!.loadUrl(pdfUrl);
      } else if (t == 'media' && (mime.startsWith('video/') || mime.startsWith('audio/'))) {
        final url = info['url'] as String;
        final tag = mime.startsWith('video/') ? 'video' : 'audio';
        _avCtrl = WebviewController();
        await _avCtrl!.initialize();
        await _avCtrl!.loadStringContent(_mediaHtml(url, mime, tag));
      }
      setState(() { _info = info; _loading = false; });
    } catch (e, stack) {
      appLog('[PREVIEW] ERROR: $e\n$stack');
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _mediaHtml(String url, String mime, String tag) {
    final dim = tag == 'video' ? 'width:100%;height:100%' : 'width:100%;max-width:480px';
    return '''
<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{margin:0;background:#000;display:flex;align-items:center;justify-content:center;height:100vh;overflow:hidden}
$tag{$dim;outline:none}</style></head><body>
<$tag controls autoplay src="$url" type="$mime" style="$dim"></$tag>
</body></html>''';
  }

  Future<void> _cleanup() async {
    if (_tempPath != null) {
      try {
        await _api.dio.post('/preview/close/${widget.fileId}');
        appLog('[PREVIEW] cleaned up temp file: $_tempPath');
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _pdfCtrl?.dispose();
    _avCtrl?.dispose();
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      );
    } else {
      final info = _info!;
      final type = info['type'] as String;
      final mime = info['mime_type'] as String? ?? '';
      final url = info['url'] as String? ?? '';
      final name = info['name'] as String? ?? '';

      if (type == 'media' && mime == 'application/pdf' && _pdfCtrl != null) {
        content = Webview(_pdfCtrl!);
      } else if (type == 'media' && (mime.startsWith('video/') || mime.startsWith('audio/')) && _avCtrl != null) {
        content = Webview(_avCtrl!);
      } else if (type == 'media' && mime.startsWith('image/')) {
        content = InteractiveViewer(
          child: Center(child: Image.network(url)),
        );
      } else if (type == 'raw' || (type == 'media' && mime.startsWith('text/'))) {
        content = _TextPreview(url: url, name: name, theme: theme);
      } else {
        content = Center(child: Text('不支持预览此文件类型 ($mime)'));
      }
    }

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_info?['name'] ?? '预览'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ),
        body: content,
      ),
    );
  }
}

class _TextPreview extends StatefulWidget {
  final String url;
  final String name;
  final ThemeData theme;

  const _TextPreview({
    required this.url,
    required this.name,
    required this.theme,
  });

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final resp = await Dio().get(widget.url);
      setState(() => _text = resp.data.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text('加载失败: $_error'));
    }
    if (_text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isDark = widget.theme.brightness == Brightness.dark;
    return Container(
      color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          _text!,
          style: TextStyle(
            fontSize: 14,
            height: 1.7,
            fontFamily: 'monospace',
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
