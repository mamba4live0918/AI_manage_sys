import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class ResponsiveScaffold extends ConsumerWidget {
  final Widget child;
  const ResponsiveScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS || MediaQuery.of(context).size.width >= 768;

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex(context),
              onDestinationSelected: (i) => _navigate(context, i),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.all(12),
                child: CircleAvatar(child: Text(auth.user?.username[0].toUpperCase() ?? '?')),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.logout),
                tooltip: '退出',
                onPressed: () => ref.read(authProvider.notifier).logout(),
              ),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.folder), label: Text('文件')),
                NavigationRailDestination(icon: Icon(Icons.security), label: Text('权限')),
                NavigationRailDestination(icon: Icon(Icons.history), label: Text('审计')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    // Mobile: bottom navigation
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (i) => _navigate(context, i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: '文件'),
          NavigationDestination(icon: Icon(Icons.security_outlined), selectedIcon: Icon(Icons.security), label: '权限'),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: '审计'),
        ],
      ),
    );
  }

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc.startsWith('/files')) return 0;
    if (loc.startsWith('/permissions')) return 1;
    if (loc.startsWith('/audit')) return 2;
    return 0;
  }

  void _navigate(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/files');
      case 1: context.go('/permissions');
      case 2: context.go('/audit');
    }
  }
}
