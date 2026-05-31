import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'services/api_client.dart';
import 'pages/auth/login_page.dart';
import 'pages/files/file_list_page.dart';
import 'pages/preview/preview_page.dart';

import 'pages/audit/audit_log_page.dart';
import 'pages/ip/ip_dashboard_page.dart';
import 'pages/marketing/marketing_dashboard_page.dart';
import 'pages/bidding/bidding_dashboard_page.dart';
import 'pages/pm/pm_dashboard_page.dart';
import 'pages/hr/hr_dashboard_page.dart';
import 'pages/finance/finance_dashboard_page.dart';
import 'pages/dashboard/dashboard_page.dart';
import 'widgets/responsive_scaffold.dart';
import 'utils/app_logger.dart';

class AIManageApp extends ConsumerStatefulWidget {
  const AIManageApp({super.key});

  @override
  ConsumerState<AIManageApp> createState() => _AIManageAppState();
}

class _AIManageAppState extends ConsumerState<AIManageApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _buildRouter();
  }

  /// Determine home page based on user modules
  String _homeRoute(AuthState auth) {
    final modules = auth.user?.accessibleModules ?? [];
    // Admin/all-modules or multi-module -> overview dashboard
    if (modules.contains('dashboard') || modules.length > 3) return '/dashboard';
    // Single module -> go directly to that module
    if (modules.length == 1) return '/${modules.first}';
    // Default
    return '/dashboard';
  }

  String? _routeModule(String location) {
    if (location.startsWith('/dashboard')) return 'dashboard';
    if (location.startsWith('/files')) return 'files';
    if (location.startsWith('/ip')) return 'ip';
    if (location.startsWith('/audit')) return 'audit';
    if (location.startsWith('/marketing')) return 'marketing';
    if (location.startsWith('/bidding')) return 'bidding';
    if (location.startsWith('/pm')) return 'pm';
    if (location.startsWith('/hr')) return 'hr';
    if (location.startsWith('/finance')) return 'finance';
    return null;
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/loading',
      redirect: (context, state) {
        final auth = ref.read(authProvider);
        final loc = state.matchedLocation;

        if (!auth.isInitialized) return '/loading';
        if (loc == '/loading') {
          return auth.isLoggedIn ? _homeRoute(auth) : '/login';
        }
        if (!auth.isLoggedIn && loc != '/login') return '/login';
        if (auth.isLoggedIn && loc == '/login') return _homeRoute(auth);
        if (loc == '/users') return '/hr';

        // module access check
        if (auth.isLoggedIn && auth.user != null && !auth.user!.isAdmin) {
          final module = _routeModule(loc);
          if (module != null && !auth.user!.accessibleModules.contains(module)) {
            return _homeRoute(auth);
          }
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/loading',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: const LoginPage(),
          ),
        ),
        ShellRoute(
          pageBuilder: (context, state, child) => NoTransitionPage(
            key: state.pageKey,
            child: ResponsiveScaffold(child: child),
          ),
          routes: [
            GoRoute(
              path: '/dashboard',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const DashboardPage(),
              ),
            ),
            GoRoute(
              path: '/files',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const FileListPage(),
              ),
              routes: [
                GoRoute(
                  path: 'preview/:fileId',
                  pageBuilder: (context, state) => NoTransitionPage(
                    key: state.pageKey,
                    child: PreviewPage(
                      fileId: state.pathParameters['fileId']!,
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/ip',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const IpDashboardPage(),
              ),
            ),
            GoRoute(
              path: '/audit',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const AuditLogPage(),
              ),
            ),
            GoRoute(
              path: '/marketing',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const MarketingDashboardPage(),
              ),
            ),
            GoRoute(
              path: '/bidding',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const BiddingDashboardPage(),
              ),
            ),
            GoRoute(
              path: '/pm',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const PmDashboardPage(),
              ),
            ),
            GoRoute(
              path: '/hr',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const HrDashboardPage(),
              ),
            ),
            GoRoute(
              path: '/finance',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const FinanceDashboardPage(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider);
    appLog('[APP build] isInitialized=${auth.isInitialized} isLoggedIn=${auth.isLoggedIn}');

    ref.listen(authProvider, (prev, next) {
      // Handle initial auth check completion
      if (prev?.isInitialized != true && next.isInitialized) {
        final home = _homeRoute(next);
        appLog('[APP] auth initialized, going to ${next.isLoggedIn ? home : '/login'}');
        _router.go(next.isLoggedIn ? home : '/login');
        return;
      }
      if (prev?.isLoggedIn != true && next.isLoggedIn) {
        final home = _homeRoute(next);
        appLog('[APP] redirect: $home');
        _router.go(home);
      } else if (prev?.isLoggedIn == true && !next.isLoggedIn) {
        appLog('[APP] redirect: /login');
        _router.go('/login');
      }
    });

    appLog('[APP] building MaterialApp.router');
    ApiClient().onUnauthorized = () => ref.read(authProvider.notifier).logout();

    return MaterialApp.router(
      title: 'AI管理系统',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
