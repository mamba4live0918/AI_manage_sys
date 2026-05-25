import 'package:flutter/material.dart';
import '../config/theme.dart';

class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const Shimmer({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 6,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(_anim.value - 1, 0),
              end: Alignment(_anim.value + 1, 0),
              colors: [
                isDark ? AppTheme.darkElevated : const Color(0xFFE8E8ED),
                isDark ? AppTheme.darkElevated : const Color(0xFFE8E8ED),
                isDark ? const Color(0xFF3A3A3C) : const Color(0xFFDCDCE0),
                isDark ? AppTheme.darkElevated : const Color(0xFFE8E8ED),
                isDark ? AppTheme.darkElevated : const Color(0xFFE8E8ED),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int count;
  const ShimmerList({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: count,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            const Shimmer(width: 36, height: 36, radius: 9),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Shimmer(width: 100 + (i * 41 % 120), height: 15, radius: 5),
                  const SizedBox(height: 8),
                  Shimmer(width: 60 + (i * 37 % 80), height: 12, radius: 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
