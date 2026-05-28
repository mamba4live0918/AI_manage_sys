import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── iOS system colors ──
  static const blue = Color(0xFF007AFF);
  static const green = Color(0xFF34C759);
  static const red = Color(0xFFFF3B30);
  static const orange = Color(0xFFFF9500);
  static const yellow = Color(0xFFFFCC00);
  static const purple = Color(0xFFAF52DE);
  static const teal = Color(0xFF5AC8FA);
  static const pink = Color(0xFFFF2D55);

  // Light surfaces
  static const lightBg = Color(0xFFF2F2F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightGrouped = Color(0xFFF2F2F7);

  // Dark surfaces
  static const darkBg = Color(0xFF000000);
  static const darkSurface = Color(0xFF1C1C1E);
  static const darkElevated = Color(0xFF2C2C2E);
  static const darkGrouped = Color(0xFF000000);

  static ThemeData get light {
    const accent = blue;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: lightSurface,
        primary: accent,
      ),
      scaffoldBackgroundColor: lightBg,
            appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          height: 1.15,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFE8E8ED),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accent.withAlpha(100),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: accent),
          foregroundColor: accent,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: lightSurface.withAlpha(180),
        indicatorColor: accent.withAlpha(25),
        selectedIconTheme: const IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: Colors.grey.shade500),
        selectedLabelTextStyle: const TextStyle(
          color: accent,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: -0.1,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 11,
        ),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        groupAlignment: -0.2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface.withAlpha(200),
        indicatorColor: accent.withAlpha(20),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        height: 82,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withAlpha(20),
        thickness: 0.5,
        space: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 0, height: 1.15),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 0, height: 1.2),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 0),
        titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        bodyLarge: TextStyle(fontSize: 17, height: 1.45, letterSpacing: -0.2),
        bodyMedium: TextStyle(fontSize: 15, height: 1.4, letterSpacing: -0.15),
        labelSmall: TextStyle(fontSize: 12, letterSpacing: 0),
      ),
    );
  }

  static ThemeData get dark {
    const accent = Color(0xFF0A84FF);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: darkSurface,
        primary: accent,
      ),
      scaffoldBackgroundColor: darkBg,
            appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          height: 1.15,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: accent.withAlpha(100),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: accent),
          foregroundColor: accent,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface.withAlpha(180),
        indicatorColor: accent.withAlpha(30),
        selectedIconTheme: const IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: Colors.grey.shade600),
        selectedLabelTextStyle: const TextStyle(
          color: accent,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: -0.1,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 11,
        ),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        groupAlignment: -0.2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface.withAlpha(220),
        indicatorColor: accent.withAlpha(30),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        height: 82,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withAlpha(15),
        thickness: 0.5,
        space: 0,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 0, height: 1.15, color: Colors.white),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 0, height: 1.2, color: Colors.white),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 0, color: Colors.white),
        titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: Colors.white),
        bodyLarge: TextStyle(fontSize: 17, height: 1.45, letterSpacing: -0.2, color: Colors.white),
        bodyMedium: TextStyle(fontSize: 15, height: 1.4, letterSpacing: -0.15, color: Colors.white),
        labelSmall: TextStyle(fontSize: 12, letterSpacing: 0, color: Colors.white),
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
