import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

const _moduleConfig = <String, _NavItem>{
  'dashboard': (Icons.home_rounded, Icons.home_outlined, '首页', '/dashboard'),
  'files': (Icons.folder_rounded, Icons.folder_outlined, '文件', '/files'),
  'ip': (Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, '讲师IP', '/ip'),
  'audit': (Icons.schedule_rounded, Icons.schedule_outlined, '审计', '/audit'),
  'users': (Icons.people_rounded, Icons.people_outline_rounded, '用户管理', '/users'),
  'marketing': (Icons.campaign_rounded, Icons.campaign_outlined, '市场部', '/marketing'),
  'bidding': (Icons.gavel_rounded, Icons.gavel_outlined, '招投标', '/bidding'),
};

typedef _NavItem = (IconData, IconData, String, String);

class ResponsiveScaffold extends ConsumerWidget {
  final Widget child;
  const ResponsiveScaffold({super.key, required this.child});

  List<MapEntry<String, _NavItem>> _navItems(AuthState auth) {
    final modules = auth.user?.accessibleModules ?? [];
    return modules
        .where((k) => _moduleConfig.containsKey(k))
        .map((k) => MapEntry(k, _moduleConfig[k]!))
        .toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (isDesktop) return _desktopLayout(context, ref, auth);
    return _mobileLayout(context, ref, auth);
  }

  Widget _desktopLayout(BuildContext context, WidgetRef ref, AuthState auth) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _navItems(auth);
    final idx = _selectedIndex(context, items);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Row(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 88,
                decoration: BoxDecoration(
                  color: (isDark ? AppTheme.darkSurface : AppTheme.lightSurface)
                      .withAlpha(isDark ? 170 : 180),
                  border: Border(
                    right: BorderSide(
                      color: (isDark ? Colors.white : Colors.black).withAlpha(10),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 48),
                    _SidebarAvatar(auth: auth),
                    const SizedBox(height: 24),
                    Expanded(
                      child: _SidebarNav(
                        items: items,
                        currentIndex: idx,
                        onTap: (i) => context.go(items[i].value.$4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SidebarAction(
                      icon: isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      label: '主题',
                      onTap: () => ref.read(themeProvider.notifier).toggle(isCurrentlyDark: isDark),
                    ),
                    const SizedBox(height: 2),
                    _SidebarAction(
                      icon: Icons.logout_rounded,
                      label: '退出',
                      onTap: () => ref.read(authProvider.notifier).logout(),
                      destructive: true,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _mobileLayout(BuildContext context, WidgetRef ref, AuthState auth) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _navItems(auth);
    final idx = _selectedIndex(context, items);

    return Scaffold(
      extendBody: true,
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: child,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? AppTheme.darkSurface : AppTheme.lightSurface)
                  .withAlpha(isDark ? 200 : 200),
              border: Border(
                top: BorderSide(
                  color: (isDark ? Colors.white : Colors.black).withAlpha(10),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (int i = 0; i < items.length; i++)
                      _TabItem(
                        icon: items[i].value.$1,
                        outline: items[i].value.$2,
                        label: items[i].value.$3,
                        selected: idx == i,
                        onTap: () => context.go(items[i].value.$4),
                      ),
                    _TabItem(
                      icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      outline: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      label: '主题',
                      selected: false,
                      onTap: () => ref.read(themeProvider.notifier).toggle(isCurrentlyDark: isDark),
                    ),
                    _TabItem(
                      icon: Icons.person_rounded,
                      outline: Icons.person_outline_rounded,
                      label: '退出',
                      selected: false,
                      onTap: () => ref.read(authProvider.notifier).logout(),
                      destructive: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _selectedIndex(BuildContext context, List<MapEntry<String, _NavItem>> items) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < items.length; i++) {
      if (loc.startsWith(items[i].value.$4)) return i;
    }
    return 0;
  }
}

// ── Sidebar components ──

class _SidebarAvatar extends StatelessWidget {
  final AuthState auth;
  const _SidebarAvatar({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.blue, Color(0xFF5856D6)],
        ),
      ),
      child: Center(
        child: Text(
          auth.user?.username[0].toUpperCase() ?? '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _SidebarNav extends StatelessWidget {
  final List<MapEntry<String, _NavItem>> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _SidebarNav({required this.items, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++)
          _SidebarNavItem(
            selected: currentIndex == i,
            icon: items[i].value.$1,
            outline: items[i].value.$2,
            label: items[i].value.$3,
            onTap: () => onTap(i),
          ),
      ],
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final IconData outline;
  final String label;
  final VoidCallback onTap;

  const _SidebarNavItem({
    required this.selected,
    required this.icon,
    required this.outline,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected
                  ? AppTheme.blue.withAlpha(isDark ? 30 : 20)
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? icon : outline,
                  size: 22,
                  color: selected
                      ? AppTheme.blue
                      : (isDark ? Colors.white : Colors.black).withAlpha(140),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? AppTheme.blue
                        : (isDark ? Colors.white : Colors.black).withAlpha(140),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _SidebarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppTheme.red
        : (Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black)
            .withAlpha(140);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(fontSize: 10, color: color, letterSpacing: -0.1)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mobile tab item ──

class _TabItem extends StatelessWidget {
  final IconData icon;
  final IconData outline;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool destructive;

  const _TabItem({
    required this.icon,
    required this.outline,
    required this.label,
    required this.selected,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppTheme.red
        : selected
            ? AppTheme.blue
            : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black)
                .withAlpha(120);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? icon : outline, size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
