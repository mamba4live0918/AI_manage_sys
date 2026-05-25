import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppTheme {
  AppTheme._();

  // ── Macaron palette ──
  static const macaronPink = Color(0xFFF4A7B9);
  static const macaronMint = Color(0xFFA8E6CF);
  static const macaronBlue = Color(0xFF88D8F5);
  static const macaronPurple = Color(0xFFC5A3D9);
  static const macaronPeach = Color(0xFFFFD3B6);
  static const macaronLavender = Color(0xFFB8B5E8);
  static const macaronCream = Color(0xFFFFF5E8);

  static ThemeData get light {
    const seed = macaronPink;
    return ThemeData(
      colorSchemeSeed: seed,
      useMaterial3: true,
      brightness: Brightness.light,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: seed.withAlpha(20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: seed, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: seed.withAlpha(12),
        indicatorColor: seed.withAlpha(40),
        selectedIconTheme: IconThemeData(color: seed),
        selectedLabelTextStyle: TextStyle(color: seed, fontWeight: FontWeight.w600),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        groupAlignment: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: seed.withAlpha(40),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 65,
      ),
    );
  }

  static ThemeData get dark {
    const seed = Color(0xFFE8A0BF);
    return ThemeData(
      colorSchemeSeed: seed,
      useMaterial3: true,
      brightness: Brightness.dark,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: seed.withAlpha(20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: seed, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        selectedIconTheme: IconThemeData(color: seed),
        selectedLabelTextStyle: TextStyle(color: seed, fontWeight: FontWeight.w600),
        labelType: NavigationRailLabelType.all,
        useIndicator: true,
        groupAlignment: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 65,
      ),
    );
  }

  /// Slide + fade page transition
  static Page<T> pageTransition<T>({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
    Offset begin = const Offset(0.08, 0),
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: begin,
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1)
                .chain(CurveTween(curve: Curves.easeOut))
                .animate(animation),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 250),
    );
  }
}
