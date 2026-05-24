import 'package:flutter/material.dart';

class Watermark extends StatelessWidget {
  final String username;
  final String department;
  final Widget child;

  const Watermark({
    super.key,
    required this.username,
    required this.department,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        IgnorePointer(
          child: CustomPaint(
            painter: _WatermarkPainter(
              text: '$username | $department | ${DateTime.now().toString().substring(0, 16)}',
            ),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}

class _WatermarkPainter extends CustomPainter {
  final String text;
  _WatermarkPainter({required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Colors.grey.withValues(alpha: 0.08), fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final spacing = 200.0;
    for (double y = -size.height; y < size.height * 2; y += spacing) {
      for (double x = -size.width; x < size.width * 2; x += spacing) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.4);
        textPainter.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
