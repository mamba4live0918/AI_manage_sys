import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'services/api_client.dart';
import 'pages/auth/login_page.dart';
import 'pages/files/file_list_page.dart';
import 'pages/preview/preview_page.dart';
import 'pages/permissions/permissions_page.dart';
import 'pages/audit/audit_log_page.dart';
import 'widgets/responsive_scaffold.dart';

class AIManageApp extends StatelessWidget {
  const AIManageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final auth = ref.watch(authProvider);
        if (!auth.isInitialized) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        final router = GoRouter(
          initialLocation: auth.isLoggedIn ? '/files' : '/login',
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
              pageBuilder: (context, state) => AppTheme.pageTransition(
                context: context,
                state: state,
                begin: const Offset(0, 0.06),
                child: const LoginPage(),
              ),
            ),
            ShellRoute(
              builder: (_, __, child) => ResponsiveScaffold(child: child),
              routes: [
                GoRoute(
                  path: '/files',
                  pageBuilder: (context, state) => AppTheme.pageTransition(
                    context: context,
                    state: state,
                    child: const FileListPage(),
                  ),
                  routes: [
                    GoRoute(
                      path: 'preview/:fileId',
                      pageBuilder: (context, state) {
                        final fileId = state.pathParameters['fileId']!;
                        return AppTheme.pageTransition(
                          context: context,
                          state: state,
                          begin: const Offset(0.12, 0),
                          child: PreviewPage(fileId: fileId),
                        );
                      },
                    ),
                  ],
                ),
                GoRoute(
                  path: '/permissions',
                  pageBuilder: (context, state) => AppTheme.pageTransition(
                    context: context,
                    state: state,
                    child: const PermissionsPage(),
                  ),
                ),
                GoRoute(
                  path: '/audit',
                  pageBuilder: (context, state) => AppTheme.pageTransition(
                    context: context,
                    state: state,
                    child: const AuditLogPage(),
                  ),
                ),
              ],
            ),
          ],
        );

        // Wire 401 handler
        ApiClient().onUnauthorized = () => ref.read(authProvider.notifier).logout();

        return MaterialApp.router(
          title: 'AI管理系统',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          routerConfig: router,
        );
      },
    );
  }
}
