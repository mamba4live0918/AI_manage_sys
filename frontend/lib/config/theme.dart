import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Accent ──
  static const accent = Color(0xFF3B82F6); // desaturated blue, not iOS #007AFF

  // ── Semantic ──
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);
  static const teal = Color(0xFF14B8A6);
  static const purple = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);

  // ── Light surfaces (cream + glass) ──
  static const cream = Color(0xFFFAF7F2);              // page background
  static const creamSurface = Color(0xFFFFFFFF);       // card surface (pure white base)
  static const creamElevated = Color(0xFFF5F2EC);      // subtle raised
  static const lightGlass = Color(0xB8FFFFFF);          // glass: 72% opacity white

  // ── Dark surfaces (warm charcoal) ──
  static const darkBg = Color(0xFF1A1A18);              // page background
  static const darkSurface = Color(0xFF252523);         // card surface
  static const darkElevated = Color(0xFF2E2E2C);       // raised surface
  static const darkGlass = Color(0xB8252523);           // glass: 72% opacity dark

  // ── Light Theme ──

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const ['Noto Sans SC', 'PingFang SC', 'Microsoft YaHei', 'sans-serif'],
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: creamSurface,
        primary: accent,
      ),
      scaffoldBackgroundColor: cream,

      // ── AppBar (enterprise compact) ──
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Color(0xFF1A1A18),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),

      // ── Cards (glass border, subtle shadow) ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: lightGlass,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withAlpha(180), width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withAlpha(180),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: const Color(0xFF1A1A18).withAlpha(15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: const Color(0xFF1A1A18).withAlpha(15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF78716C)),
      ),

      // ── Buttons (compact on desktop) ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(120, 42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: BorderSide(color: const Color(0xFF1A1A18).withAlpha(30)),
          foregroundColor: const Color(0xFF1A1A18),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Navigation ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: lightGlass,
        indicatorColor: accent.withAlpha(25),
        selectedIconTheme: const IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: const Color(0xFF78716C).withAlpha(140)),
        selectedLabelTextStyle: const TextStyle(
          color: accent, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: -0.1,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: const Color(0xFF78716C).withAlpha(140), fontSize: 11,
        ),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        groupAlignment: -0.2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightGlass,
        indicatorColor: accent.withAlpha(20),
        elevation: 0, surfaceTintColor: Colors.transparent, shadowColor: Colors.transparent,
        height: 82,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // ── Dividers ──
      dividerTheme: DividerThemeData(
        color: const Color(0xFF1A1A18).withAlpha(12),
        thickness: 0.5, space: 0,
      ),

      // ── Typography (enterprise scale) ──
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF1A1A18), letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1A18), letterSpacing: -0.3),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1A1A18)),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A18)),
        bodyLarge: TextStyle(fontSize: 15, color: Color(0xFF1A1A18), height: 1.45),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF44403C), height: 1.4),
        labelSmall: TextStyle(fontSize: 12, color: Color(0xFF78716C)),
      ),
    );
  }

  // ── Dark Theme ──

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const ['Noto Sans SC', 'PingFang SC', 'Microsoft YaHei', 'sans-serif'],
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B82F6),
        brightness: Brightness.dark,
        surface: darkSurface,
        primary: const Color(0xFF3B82F6),
      ),
      scaffoldBackgroundColor: darkBg,

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Color(0xFFE7E5E0),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),

      // ── Cards (dark glass) ──
      cardTheme: CardThemeData(
        elevation: 0,
        color: darkGlass,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withAlpha(10), width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkElevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withAlpha(10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withAlpha(10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 14, color: Color(0xFF78716C)),
      ),

      // ── Buttons ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(120, 42),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          side: BorderSide(color: Colors.white.withAlpha(30)),
          foregroundColor: const Color(0xFFE7E5E0),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // ── Navigation ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkGlass,
        indicatorColor: accent.withAlpha(30),
        selectedIconTheme: const IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: const Color(0xFF78716C).withAlpha(160)),
        selectedLabelTextStyle: const TextStyle(
          color: accent, fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: -0.1,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: const Color(0xFF78716C).withAlpha(160), fontSize: 11,
        ),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        groupAlignment: -0.2,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkGlass,
        indicatorColor: accent.withAlpha(30),
        elevation: 0, surfaceTintColor: Colors.transparent, shadowColor: Colors.transparent,
        height: 82,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      // ── Dividers ──
      dividerTheme: DividerThemeData(
        color: Colors.white.withAlpha(10),
        thickness: 0.5, space: 0,
      ),

      // ── Typography ──
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFE7E5E0), letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFE7E5E0), letterSpacing: -0.3),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFE7E5E0)),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFE7E5E0)),
        bodyLarge: TextStyle(fontSize: 15, color: Color(0xFFE7E5E0), height: 1.45),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFA8A29E), height: 1.4),
        labelSmall: TextStyle(fontSize: 12, color: Color(0xFF78716C)),
      ),
    );
  }
}

/// Subtle separator line
class AppSeparator extends StatelessWidget {
  final double indent;
  const AppSeparator({super.key, this.indent = 16});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.only(left: indent),
      height: 0.5,
      color: isDark ? Colors.white.withAlpha(10) : const Color(0xFF1A1A18).withAlpha(12),
    );
  }
}

/// Grouped section container
class AppGroupedSection extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;
  const AppGroupedSection({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final separatorColor = isDark ? Colors.white.withAlpha(8) : const Color(0xFF1A1A18).withAlpha(8);

    return Padding(
      padding: padding,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: isDark ? AppTheme.darkSurface : AppTheme.creamSurface,
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
