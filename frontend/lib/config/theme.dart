import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Accent ──
  static const accent = Color(0xFF4F46E5);
  static const accentLight = Color(0xFF818CF8);

  // ── Status colors ──
  static const blue = Color(0xFF4F46E5);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);
  static const purple = Color(0xFF8B5CF6);
  static const teal = Color(0xFF14B8A6);
  static const pink = Color(0xFFEC4899);

  // Light — Indigo glass
  static const lightBgStart = Color(0xFFE8EAF0);
  static const lightBgEnd = Color(0xFFEBEDF3);
  static const lightSurface = Color(0x7AFFFFFF);
  static const lightSurfaceSolid = Color(0xFFFFFFFF);
  static const lightBorder = Color(0x2E6366F1);
  static const lightText = Color(0xFF1A1A2E);
  static const lightTextSecondary = Color(0xFF6B6B8A);
  static const lightAccentBg = Color(0x144F46E5);

  // Dark — Clean charcoal
  static const darkBg = Color(0xFF0D0F13);
  static const darkSurface = Color(0xFF16181D);
  static const darkSurfaceAlt = Color(0xFF1F2228);
  static const darkBorder = Color(0xFF2A2D33);
  static const darkText = Color(0xFFEDEDED);
  static const darkTextSecondary = Color(0xFF9CA3AF);
  static const darkAccentBg = Color(0x1A4F46E5);

  // ── Backward compatibility aliases ──
  static const lightBg = lightBgStart;
  static const darkElevated = darkSurfaceAlt;
  static const lightGrouped = lightBgStart;
  static const darkGrouped = darkBg;
  static const yellow = Color(0xFFEAB308);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Microsoft YaHei',
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: lightSurfaceSolid,
        primary: accent,
      ),
      scaffoldBackgroundColor: lightBgStart,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: lightText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightSurfaceSolid,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: lightBorder, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: lightBorder,
        thickness: 0.5,
        space: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurfaceSolid,
        indicatorColor: lightAccentBg,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: lightSurfaceSolid,
        indicatorColor: lightAccentBg,
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Microsoft YaHei',
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: darkSurface,
        primary: accentLight,
      ),
      scaffoldBackgroundColor: darkBg,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: darkBorder, width: 0.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: darkBorder,
        thickness: 0.5,
        space: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentLight,
          foregroundColor: darkBg,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: darkAccentBg,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface,
        indicatorColor: darkAccentBg,
      ),
    );
  }
}

/// Separator line (iOS style)
class IosSeparator extends StatelessWidget {
  final double indent;
  const IosSeparator({super.key, this.indent = 16});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.only(left: indent),
      height: 0.5,
      color: isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(20),
    );
  }
}

/// Grouped section container (iOS Settings style)
class IosGroupedSection extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const IosGroupedSection({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final separatorColor = isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(12);

    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 16, endIndent: 0, color: separatorColor),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
