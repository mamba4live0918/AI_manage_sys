import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/finance_models.dart';
import '../services/api_client.dart';

class FinanceDashboardState {
  final FinanceDashboardData? data;
  final bool loading;
  final String? error;
  const FinanceDashboardState({this.data, this.loading = false, this.error});
}

class FinanceDashboardNotifier extends StateNotifier<FinanceDashboardState> {
  final ApiClient _api = ApiClient();
  FinanceDashboardNotifier() : super(const FinanceDashboardState());

  Future<void> load() async {
    state = const FinanceDashboardState(loading: true);
    try {
      final resp = await _api.dio.get('/api/finance/dashboard');
      state = FinanceDashboardState(data: FinanceDashboardData.fromJson(resp.data));
    } catch (e) {
      state = FinanceDashboardState(error: e.toString());
    }
  }
}

final financeDashboardProvider = StateNotifierProvider<FinanceDashboardNotifier, FinanceDashboardState>(
  (ref) => FinanceDashboardNotifier(),
);

// Invoices
class FinanceInvoiceState {
  final List<InvoiceData> items;
  final bool loading;
  const FinanceInvoiceState({this.items = const [], this.loading = false});
}

class FinanceInvoiceNotifier extends StateNotifier<FinanceInvoiceState> {
  FinanceInvoiceNotifier() : super(const FinanceInvoiceState());

  Future<void> load({String projectId = '', String status = ''}) async {
    state = const FinanceInvoiceState(loading: true);
    try {
      final params = <String, String>{};
      if (projectId.isNotEmpty) params['project_id'] = projectId;
      if (status.isNotEmpty) params['status'] = status;
      final resp = await _api.dio.get('/api/finance/invoices', queryParameters: params.isNotEmpty ? params : null);
      final items = (resp.data['items'] as List).map((j) => InvoiceData.fromJson(j)).toList();
      state = FinanceInvoiceState(items: items);
    } catch (e) {
      state = const FinanceInvoiceState();
    }
  }
}

final financeInvoiceProvider = StateNotifierProvider<FinanceInvoiceNotifier, FinanceInvoiceState>(
  (ref) => FinanceInvoiceNotifier(),
);

// Budgets
class FinanceBudgetState {
  final List<BudgetData> items;
  final bool loading;
  const FinanceBudgetState({this.items = const [], this.loading = false});
}

class FinanceBudgetNotifier extends StateNotifier<FinanceBudgetState> {
  FinanceBudgetNotifier() : super(const FinanceBudgetState());

  Future<void> load() async {
    state = const FinanceBudgetState(loading: true);
    try {
      final resp = await _api.dio.get('/api/finance/budgets');
      final items = (resp.data['items'] as List).map((j) => BudgetData.fromJson(j)).toList();
      state = FinanceBudgetState(items: items);
    } catch (e) {
      state = const FinanceBudgetState();
    }
  }
}

final financeBudgetProvider = StateNotifierProvider<FinanceBudgetNotifier, FinanceBudgetState>(
  (ref) => FinanceBudgetNotifier(),
);
