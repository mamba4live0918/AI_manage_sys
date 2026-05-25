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
              path: '/users',
              pageBuilder: (context, state) => NoTransitionPage(
                key: state.pageKey,
                child: const UsersPage(),
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
    appLog('[APP build] isInitialized=${auth.isInitialized} isLoggedIn=${auth.isLoggedIn} error=${auth.error}');

    ref.listen(authProvider, (prev, next) {
      if (prev?.isLoggedIn != true && next.isLoggedIn) {
        appLog('[APP] redirect: /files');
        _router.go('/files');
      } else if (prev?.isLoggedIn == true && !next.isLoggedIn) {
        appLog('[APP] redirect: /login');
        _router.go('/login');
      }
    });

    if (!auth.isInitialized) {
      appLog('[APP] showing loading spinner (not initialized)');
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

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
