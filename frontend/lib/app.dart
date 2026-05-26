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
import 'pages/permissions/users_page.dart';
import 'pages/audit/audit_log_page.dart';
import 'pages/ip/ip_dashboard_page.dart';
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

  String? _routeModule(String location) {
    if (location.startsWith('/dashboard')) return 'dashboard';
    if (location.startsWith('/files')) return 'files';
    if (location.startsWith('/ip')) return 'ip';
    if (location.startsWith('/audit')) return 'audit';
    if (location.startsWith('/users')) return 'users';
    if (location.startsWith('/marketing')) return 'marketing';
    if (location.startsWith('/bidding')) return 'bidding';
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
          return auth.isLoggedIn ? '/dashboard' : '/login';
        }
        if (!auth.isLoggedIn && loc != '/login') return '/login';
        if (auth.isLoggedIn && loc == '/login') return '/dashboard';

        // module access check
        if (auth.isLoggedIn && auth.user != null && !auth.user!.isAdmin) {
          final module = _routeModule(loc);
          if (module != null && !auth.user!.accessibleModules.contains(module)) {
            return '/dashboard';
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
              path: '/users',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const UsersPage(),
              ),
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
        appLog('[APP] auth initialized, going to ${next.isLoggedIn ? '/dashboard' : '/login'}');
        _router.go(next.isLoggedIn ? '/dashboard' : '/login');
        return;
      }
      if (prev?.isLoggedIn != true && next.isLoggedIn) {
        appLog('[APP] redirect: /dashboard');
        _router.go('/dashboard');
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
