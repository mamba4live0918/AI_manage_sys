import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/api_client.dart';

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
    final token = await _api.loadToken();
    if (token != null) {
      try {
        final resp = await _api.dio.get('/auth/me');
        state = AuthState(
          user: User.fromJson(resp.data),
          token: token,
          isInitialized: true,
        );
        return;
      } catch (_) {
        await _api.clearToken();
      }
    }
    state = const AuthState(isInitialized: true);
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
