import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import 'search_dialog.dart';

const _moduleConfig = <String, _NavItem>{
  'dashboard': (Icons.home_rounded, Icons.home_outlined, '首页', '/dashboard'),
  'files': (Icons.folder_rounded, Icons.folder_outlined, '文件', '/files'),
  'ip': (Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, '讲师IP', '/ip'),
  'audit': (Icons.schedule_rounded, Icons.schedule_outlined, '审计', '/audit'),
  'marketing': (Icons.campaign_rounded, Icons.campaign_outlined, '市场部', '/marketing'),
  'bidding': (Icons.gavel_rounded, Icons.gavel_outlined, '招投标', '/bidding'),
  'pm': (Icons.engineering_rounded, Icons.engineering_outlined, '项目管理', '/pm'),
  'hr': (Icons.people_rounded, Icons.people_outline_rounded, 'HR', '/hr'),
  'finance': (Icons.account_balance_rounded, Icons.account_balance_outlined, '财务', '/finance'),
};

typedef _NavItem = (IconData, IconData, String, String);

class ResponsiveScaffold extends ConsumerStatefulWidget {
  final Widget child;
  const ResponsiveScaffold({super.key, required this.child});

  @override
  ConsumerState<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends ConsumerState<ResponsiveScaffold> {
  bool _sidebarCollapsed = false;

  List<MapEntry<String, _NavItem>> _navItems(AuthState auth) {
    final modules = auth.user?.accessibleModules ?? [];
    return modules
        .where((k) => _moduleConfig.containsKey(k))
        .map((k) => MapEntry(k, _moduleConfig[k]!))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (isDesktop) return _desktopLayout(auth);
    return _mobileLayout(auth);
  }

  // ── Desktop layout ──

  Widget _desktopLayout(AuthState auth) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _navItems(auth);
    final idx = _selectedIndex(context, items);
    final collapsed = _sidebarCollapsed;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: collapsed ? 56 : 200,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
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
                      const SizedBox(height: 12),
                      // collapse toggle — right-aligned
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: _CollapseToggle(
                            collapsed: collapsed,
                            isDark: isDark,
                            onTap: () => setState(() => _sidebarCollapsed = !collapsed),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!collapsed) ...[
                        _SidebarLogo(auth: auth),
                        const SizedBox(height: 20),
                      ],
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: collapsed
                              ? _SidebarNavCollapsed(
                                  items: items,
                                  currentIndex: idx,
                                  onTap: (i) => context.go(items[i].value.$4),
                                )
                              : _SidebarNav(
                                  items: items,
                                  currentIndex: idx,
                                  onTap: (i) => context.go(items[i].value.$4),
                                ),
                        ),
                      ),
                      if (!collapsed) ...[
                        const SizedBox(height: 8),
                        const Divider(height: 1, indent: 14, endIndent: 14),
                        const SizedBox(height: 8),
                        _SidebarAction(
                          icon: Icons.search_rounded,
                          label: '搜索',
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => const SearchDialog(),
                          ),
                        ),
                        const SizedBox(height: 2),
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
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  // ── Mobile layout ──

  bool _mobileDrawerOpen = false;

  Widget _mobileLayout(AuthState auth) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _navItems(auth);
    final idx = _selectedIndex(context, items);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: Stack(
        children: [
          // main content with header
          Column(
            children: [
              // thin transparent toolbar so burger doesn't overlap content
              Container(
                height: topPadding + 44,
                padding: EdgeInsets.only(top: topPadding + 4, left: 12),
                alignment: Alignment.centerLeft,
                child: _MobileBurger(
                  isDark: isDark,
                  onTap: () => setState(() => _mobileDrawerOpen = true),
                ),
              ),
              Expanded(child: widget.child),
            ],
          ),

          // backdrop
          if (_mobileDrawerOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _mobileDrawerOpen = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  color: Colors.black.withAlpha(_mobileDrawerOpen ? 120 : 0),
                ),
              ),
            ),

          // sliding sidebar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: _mobileDrawerOpen ? 0 : -180,
            top: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  width: 180,
                  decoration: BoxDecoration(
                    color: (isDark ? AppTheme.darkSurface : AppTheme.lightSurface)
                        .withAlpha(isDark ? 220 : 230),
                    border: Border(
                      right: BorderSide(
                        color: (isDark ? Colors.white : Colors.black).withAlpha(15),
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: topPadding + 16),
                      _MobileBurger(
                        isDark: isDark,
                        onTap: () => setState(() => _mobileDrawerOpen = false),
                        closeIcon: true,
                      ),
                      const SizedBox(height: 8),
                      _SidebarLogo(auth: auth),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _SidebarNav(
                            items: items,
                            currentIndex: idx,
                            onTap: (i) {
                              context.go(items[i].value.$4);
                              setState(() => _mobileDrawerOpen = false);
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 14, endIndent: 14),
                      const SizedBox(height: 8),
                      _SidebarAction(
                        icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        label: '主题',
                        onTap: () {
                          ref.read(themeProvider.notifier).toggle(isCurrentlyDark: isDark);
                          setState(() => _mobileDrawerOpen = false);
                        },
                      ),
                      const SizedBox(height: 2),
                      _SidebarAction(
                        icon: Icons.logout_rounded,
                        label: '退出',
                        onTap: () {
                          ref.read(authProvider.notifier).logout();
                          setState(() => _mobileDrawerOpen = false);
                        },
                        destructive: true,
                      ),
                      SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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

// ── Collapse toggle ──

class _CollapseToggle extends StatelessWidget {
  final bool collapsed;
  final bool isDark;
  final VoidCallback onTap;
  const _CollapseToggle({required this.collapsed, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = (isDark ? Colors.white : Colors.black).withAlpha(100);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 32,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: color.withAlpha(20),
        ),
        child: Icon(
          collapsed ? Icons.menu_rounded : Icons.menu_open_rounded,
          size: 16,
          color: color,
        ),
      ),
    );
  }
}

// ── Sidebar components ──

class _SidebarLogo extends StatelessWidget {
  final AuthState auth;
  const _SidebarLogo({required this.auth});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppTheme.darkText : AppTheme.lightText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Row(children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: const LinearGradient(colors: [AppTheme.accent, AppTheme.accentLight]),
          ),
          child: const Icon(Icons.hexagon_rounded, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AI 管理',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg, letterSpacing: -0.3)),
          Text(auth.user?.department ?? '企业版',
              style: TextStyle(
                  fontSize: 9,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
        ]),
      ]),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupColor = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    final mainItems = items.take(4).toList();
    final bizItems = items.length > 4 ? items.skip(4).toList() : <MapEntry<String, _NavItem>>[];

    return Column(mainAxisSize: MainAxisSize.min, children: [
      _GroupLabel('主要', groupColor),
      for (int i = 0; i < mainItems.length; i++)
        _SidebarNavItem(
          selected: currentIndex == i,
          icon: mainItems[i].value.$1,
          outline: mainItems[i].value.$2,
          label: mainItems[i].value.$3,
          onTap: () => onTap(i),
        ),
      if (bizItems.isNotEmpty) ...[
        const SizedBox(height: 16),
        _GroupLabel('业务', groupColor),
        for (int i = 0; i < bizItems.length; i++)
          _SidebarNavItem(
            selected: currentIndex == i + 4,
            icon: bizItems[i].value.$1,
            outline: bizItems[i].value.$2,
            label: bizItems[i].value.$3,
            onTap: () => onTap(i + 4),
          ),
      ],
    ]);
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _GroupLabel(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Text(text,
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color.withAlpha(120),
              letterSpacing: 1.5)),
    );
  }
}

class _SidebarNavCollapsed extends StatelessWidget {
  final List<MapEntry<String, _NavItem>> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _SidebarNavCollapsed({required this.items, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: currentIndex == i
                    ? AppTheme.blue.withAlpha(isDark ? 30 : 20)
                    : Colors.transparent,
              ),
              child: Icon(
                currentIndex == i ? items[i].value.$1 : items[i].value.$2,
                size: 22,
                color: currentIndex == i
                    ? AppTheme.blue
                    : (isDark ? Colors.white : Colors.black).withAlpha(140),
              ),
            ),
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
    final fg = selected
        ? (isDark ? AppTheme.accentLight : AppTheme.accent)
        : (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary);
    final bg = selected
        ? (isDark ? AppTheme.darkAccentBg : AppTheme.lightAccentBg)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: bg,
            ),
            child: Row(children: [
              Icon(selected ? icon : outline, size: 16, color: fg),
              const SizedBox(width: 10),
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: fg))),
            ]),
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
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 204,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(fontSize: 12, color: color, letterSpacing: -0.1)),
          ]),
        ),
      ),
    );
  }
}

// ── Mobile burger button ──

class _MobileBurger extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  final bool closeIcon;
  const _MobileBurger({required this.isDark, required this.onTap, this.closeIcon = false});

  @override
  Widget build(BuildContext context) {
    final color = (isDark ? Colors.white : Colors.black).withAlpha(180);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: (isDark ? Colors.white : Colors.black).withAlpha(15),
        ),
        child: Icon(
          closeIcon ? Icons.close_rounded : Icons.menu_rounded,
          size: 20,
          color: color,
        ),
      ),
    );
  }
}
