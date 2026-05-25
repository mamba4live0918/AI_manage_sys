import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../utils/app_logger.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  final bool isInitialized;
  final String? token;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isInitialized = false,
    this.token,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? error,
    bool? isInitialized,
    String? token,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isInitialized: isInitialized ?? this.isInitialized,
        token: token ?? this.token,
      );

  bool get isLoggedIn => user != null && token != null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api = ApiClient();

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    appLog('[AUTH] _init() started');
    try {
      final token = await _api.loadToken();
      appLog('[AUTH] loadToken returned: ${token != null ? "token present" : "no token"}');
      if (token != null) {
        try {
          appLog('[AUTH] calling /auth/me...');
          final resp = await _api.dio.get('/auth/me');
          appLog('[AUTH] /auth/me success: ${resp.data}');
          state = AuthState(
            user: User.fromJson(resp.data),
            token: token,
            isInitialized: true,
          );
          appLog('[AUTH] state set: isInitialized=true, user=${User.fromJson(resp.data).username}');
          return;
        } catch (e) {
          appLog('[AUTH] /auth/me failed: $e');
          await _api.clearToken();
        }
      }
      state = const AuthState(isInitialized: true);
      appLog('[AUTH] state set: isInitialized=true, no user');
    } catch (e) {
      appLog('[AUTH] _init() CRASHED: $e');
      state = const AuthState(isInitialized: true);
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _api.dio.post('/auth/login', data: {
        'username': username,
        'password': password,
      });
      final token = resp.data['access_token'] as String;
      await _api.setToken(token);
      state = AuthState(
        user: User.fromJson(resp.data['user']),
        token: token,
        isInitialized: true,
      );
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? '登录失败';
      state = state.copyWith(isLoading: false, error: msg.toString());
    }
  }

  Future<void> logout() async {
    await _api.clearToken();
    state = const AuthState(isInitialized: true);
  }

  void clearError() => state = state.copyWith(error: null);
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
