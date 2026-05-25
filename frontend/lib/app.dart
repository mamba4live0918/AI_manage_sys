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
import 'pages/permissions/permissions_page.dart';
import 'pages/audit/audit_log_page.dart';
import 'widgets/responsive_scaffold.dart';

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

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final loggedIn = ref.read(authProvider).isLoggedIn;
        final goingToLogin = state.matchedLocation == '/login';
        if (!loggedIn && !goingToLogin) return '/login';
        if (loggedIn && goingToLogin) return '/files';
        return null;
      },
      routes: [
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
              path: '/permissions',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const PermissionsPage(),
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

    ref.listen(authProvider, (prev, next) {
      if (prev?.isLoggedIn != true && next.isLoggedIn) {
        _router.go('/files');
      } else if (prev?.isLoggedIn == true && !next.isLoggedIn) {
        _router.go('/login');
      }
    });

    if (!auth.isInitialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    ApiClient().onUnauthorized = () => ref.read(authProvider.notifier).logout();

    return MaterialApp.router(
      title: 'AI管理系统',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}
