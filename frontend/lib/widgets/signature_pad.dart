import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 手写签名画板 — 返回签名的 ui.Image
class SignaturePad extends StatefulWidget {
  final VoidCallback onClear;
  const SignaturePad({super.key, required this.onClear});

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final _points = <Offset>[];
  final _strokes = <List<Offset>>[];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
          color: isDark ? Colors.grey.shade900 : Colors.white,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onPanStart: (d) {
              setState(() { _points.clear(); _points.add(d.localPosition); });
            },
            onPanUpdate: (d) {
              setState(() => _points.add(d.localPosition));
            },
            onPanEnd: (d) {
              _strokes.add(List.from(_points));
              setState(() => _points.clear());
            },
            child: CustomPaint(
              painter: _SignaturePainter(_strokes, _points, isDark),
              size: Size.infinite,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton.icon(
          onPressed: () { setState(() { _strokes.clear(); _points.clear(); }); widget.onClear(); },
          icon: const Icon(Icons.clear_rounded, size: 16),
          label: const Text('清除', style: TextStyle(fontSize: 12)),
        ),
      ]),
    ]);
  }

  Future<ui.Image?> toImage() async {
    if (_strokes.isEmpty && _points.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, 600, 180));
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint = Paint()..color = Colors.black..strokeWidth = 3..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final stroke in _strokes) {
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i] * (600 / 320), stroke[i + 1] * (600 / 320), paint);
      }
    }
    if (_points.isNotEmpty) {
      for (int i = 0; i < _points.length - 1; i++) {
        canvas.drawLine(_points[i] * (600 / 320), _points[i + 1] * (600 / 320), paint);
      }
    }
    return recorder.endRecording().toImage(600, 180);
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> current;
  final bool isDark;
  _SignaturePainter(this.strokes, this.current, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = isDark ? Colors.white : Colors.black..strokeWidth = 3..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      for (int i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
    if (current.length >= 2) {
      for (int i = 0; i < current.length - 1; i++) {
        canvas.drawLine(current[i], current[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
