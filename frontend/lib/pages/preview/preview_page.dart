import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:video_player/video_player.dart';
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
      setState(() {
        _info = resp.data;
        _loading = false;
      });
      final t = _info?['type'];
      final mime = _info?['mime_type'] ?? '';
      if (t == 'media' && mime.startsWith('video/')) {
        _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(_info!['url']))
          ..initialize().then((_) => setState(() {}));
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

      if (type == 'onlyoffice') {
        content = WebViewWidget(
          controller: WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..loadRequest(Uri.parse(_info!['config_url'] as String)),
        );
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
          child: Center(child: Image.network(_info!['url'] as String)),
        );
      } else if (type == 'media' && mime.startsWith('audio/')) {
        content = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audio_file, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(_info!['name'] ?? '', style: theme.textTheme.titleMedium),
            ],
          ),
        );
      } else {
        content = Center(child: Text('不支持预览此文件类型 ($mime)'));
      }
    }

    return Watermark(
      username: auth.user?.username ?? '',
      department: auth.user?.department ?? '',
      child: Scaffold(
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
