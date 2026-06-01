import 'package:flutter/material.dart';
import '../../config/theme.dart';

class BiddingContractDiffViewPage extends StatelessWidget {
  final String diff;
  const BiddingContractDiffViewPage({super.key, required this.diff});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('版本差异')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isDark ? AppTheme.darkSurface : const Color(0xFF1E1E1E),
          ),
          child: SelectableText(
            diff.isEmpty ? '无差异' : diff,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: isDark ? AppTheme.darkTextSecondary : const Color(0xFFD4D4D4),
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}
