import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
            GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
            ShellRoute(
              builder: (_, __, child) => ResponsiveScaffold(child: child),
              routes: [
                GoRoute(
                  path: '/files',
                  builder: (_, __) => const FileListPage(),
                  routes: [
                    GoRoute(
                      path: 'preview/:fileId',
                      builder: (_, state) =>
                          PreviewPage(fileId: state.pathParameters['fileId']!),
                    ),
                  ],
                ),
                GoRoute(
                  path: '/permissions',
                  builder: (_, __) => const PermissionsPage(),
                ),
                GoRoute(
                  path: '/audit',
                  builder: (_, __) => const AuditLogPage(),
                ),
              ],
            ),
          ],
        );

        // Wire 401 handler
        ApiClient().onUnauthorized = () => ref.read(authProvider.notifier).logout();

        return MaterialApp.router(
          title: 'AI管理系统',
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF1a56db),
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF1a56db),
            useMaterial3: true,
            brightness: Brightness.dark,
          ),
          routerConfig: router,
        );
      },
    );
  }
}
