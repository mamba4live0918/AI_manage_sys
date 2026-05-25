import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../services/api_client.dart';
import '../../providers/auth_provider.dart';
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
  WebViewController? _ooCtrl;
  VideoPlayerController? _videoCtrl;
  bool _loading = true;
  String? _error;

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
      setState(() { _info = info; });

      if (t == 'onlyoffice') {
        await _loadOnlyOffice(info['config_url'] as String);
      } else if (t == 'media' && mime.startsWith('video/')) {
        _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(info['url'] as String))
          ..initialize().then((_) => setState(() {}));
      }
    } catch (e) {
      setState(() { _error = e.toString(); });
    }
    setState(() { _loading = false; });
  }

  Future<void> _loadOnlyOffice(String configUrl) async {
    try {
      final resp = await _api.dio.get(configUrl);
      final config = Map<String, dynamic>.from(resp.data);
      final html = '''
<!DOCTYPE html>
<html style="height:100%">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <script src="http://localhost:8088/web-apps/apps/api/documents/api.js"></script>
  <style>html,body{height:100%;margin:0;padding:0}</style>
</head>
<body>
  <div id="placeholder" style="height:100%"></div>
  <script>
    new DocsAPI.DocEditor("placeholder", ${jsonEncode(config)});
  </script>
</body>
</html>''';
      _ooCtrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFF2F2F7))
        ..loadHtmlString(html, baseUrl: 'http://localhost:8088/');
    } catch (_) {}
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
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
      final type = _info!['type'] as String;
      final mime = _info!['mime_type'] as String? ?? '';
      final url = _info!['url'] as String? ?? '';
      final name = _info!['name'] as String? ?? '';

      if (type == 'onlyoffice' && _ooCtrl != null) {
        content = WebViewWidget(controller: _ooCtrl!);
      } else if (type == 'onlyoffice') {
        content = const Center(child: CircularProgressIndicator());
      } else if (type == 'media' && mime.startsWith('video/') && _videoCtrl != null) {
        content = Center(
          child: _videoCtrl!.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _videoCtrl!.value.aspectRatio,
                  child: VideoPlayer(_videoCtrl!),
                )
              : const CircularProgressIndicator(),
        );
      } else if (type == 'media' && mime.startsWith('image/')) {
        content = InteractiveViewer(
          child: Center(child: Image.network(url)),
        );
      } else if (type == 'media' && mime.startsWith('audio/')) {
        content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audio_file, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(name, style: theme.textTheme.titleMedium),
            ],
          ),
        );
      } else if (type == 'media' && mime == 'application/pdf') {
        content = WebViewWidget(
          controller: WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..loadRequest(Uri.parse(url)),
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
          actions: [
            if (_videoCtrl != null)
              IconButton(
                icon: Icon(_videoCtrl!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () => setState(() {
                  _videoCtrl!.value.isPlaying ? _videoCtrl!.pause() : _videoCtrl!.play();
                }),
              ),
          ],
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
