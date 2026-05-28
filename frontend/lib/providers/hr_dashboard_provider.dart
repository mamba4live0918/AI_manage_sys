import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/hr_dashboard.dart';
import '../services/api_client.dart';

class HrDashboardState {
  final HrDashboardData? data;
  final bool loading;
  final String? error;

  HrDashboardState({this.data, this.loading = false, this.error});

  HrDashboardState copyWith({HrDashboardData? data, bool? loading, String? error}) {
    return HrDashboardState(
      data: data ?? this.data,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class HrDashboardNotifier extends StateNotifier<HrDashboardState> {
  final ApiClient _api = ApiClient();

  HrDashboardNotifier() : super(HrDashboardState(loading: true));

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final resp = await _api.dio.get('/hr/dashboard');
      final data = HrDashboardData.fromJson(resp.data);
      state = state.copyWith(data: data, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final hrDashboardProvider = StateNotifierProvider<HrDashboardNotifier, HrDashboardState>((ref) {
  return HrDashboardNotifier();
});
