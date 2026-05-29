class InvoiceData {
  final String id;
  final String? projectId;
  final String invoiceNo;
  final double amount;
  final double taxAmount;
  final double taxRate;
  final String status;
  final String? issueDate;
  final String? dueDate;
  final String notes;
  final String sellerName;
  final String sellerTaxId;
  final String buyerName;
  final String buyerTaxId;
  final String? createdAt;

  InvoiceData({required this.id, this.projectId, required this.invoiceNo,
    required this.amount, required this.taxAmount, required this.taxRate,
    required this.status, this.issueDate, this.dueDate, required this.notes,
    this.sellerName = '', this.sellerTaxId = '', this.buyerName = '',
    this.buyerTaxId = '', this.createdAt});

  factory InvoiceData.fromJson(Map<String, dynamic> json) => InvoiceData(
    id: json['id'] ?? '',
    projectId: json['project_id'],
    invoiceNo: json['invoice_no'] ?? '',
    amount: (json['amount'] ?? 0).toDouble(),
    taxAmount: (json['tax_amount'] ?? 0).toDouble(),
    taxRate: (json['tax_rate'] ?? 0.13).toDouble(),
    status: json['status'] ?? 'draft',
    issueDate: json['issue_date'],
    dueDate: json['due_date'],
    notes: json['notes'] ?? '',
    sellerName: json['seller_name'] ?? '',
    sellerTaxId: json['seller_tax_id'] ?? '',
    buyerName: json['buyer_name'] ?? '',
    buyerTaxId: json['buyer_tax_id'] ?? '',
    createdAt: json['created_at'],
  );
}

class PaymentData {
  final String id;
  final String? invoiceId;
  final double amount;
  final String? paymentDate;
  final String paymentMethod;
  final String refNo;
  final String notes;

  PaymentData({required this.id, this.invoiceId, required this.amount,
    this.paymentDate, required this.paymentMethod, required this.refNo,
    required this.notes});

  factory PaymentData.fromJson(Map<String, dynamic> json) => PaymentData(
    id: json['id'] ?? '',
    invoiceId: json['invoice_id'],
    amount: (json['amount'] ?? 0).toDouble(),
    paymentDate: json['payment_date'],
    paymentMethod: json['payment_method'] ?? 'bank_transfer',
    refNo: json['ref_no'] ?? '',
    notes: json['notes'] ?? '',
  );
}

class BudgetData {
  final String id;
  final String? departmentId;
  final String? projectId;
  final String name;
  final int year;
  final int? quarter;
  final double totalAmount;
  final double usedAmount;
  final String status;
  final String notes;
  final String? updatedAt;

  BudgetData({required this.id, this.departmentId, this.projectId,
    required this.name, required this.year, this.quarter,
    required this.totalAmount, required this.usedAmount, required this.status,
    this.notes = '', this.updatedAt});

  factory BudgetData.fromJson(Map<String, dynamic> json) => BudgetData(
    id: json['id'] ?? '',
    departmentId: json['department_id'],
    projectId: json['project_id'],
    name: json['name'] ?? '',
    year: json['year'] ?? 2026,
    quarter: json['quarter'],
    totalAmount: (json['total_amount'] ?? 0).toDouble(),
    usedAmount: (json['used_amount'] ?? 0).toDouble(),
    status: json['status'] ?? 'active',
    notes: json['notes'] ?? '',
    updatedAt: json['updated_at'],
  );
}

class FinanceDashboardData {
  final double monthlyRevenue;
  final double totalReceivable;
  final double collectionRate;
  final List<BudgetUsage> budgetUsage;
  final List<RevenueTrend> revenueTrend12m;
  final int pendingInvoices;
  final int pendingPayments;
  final int pendingExpenses;

  FinanceDashboardData({required this.monthlyRevenue, required this.totalReceivable,
    required this.collectionRate, required this.budgetUsage, required this.revenueTrend12m,
    required this.pendingInvoices, required this.pendingPayments, required this.pendingExpenses});

  factory FinanceDashboardData.fromJson(Map<String, dynamic> json) => FinanceDashboardData(
    monthlyRevenue: (json['monthly_revenue'] ?? 0).toDouble(),
    totalReceivable: (json['total_receivable'] ?? 0).toDouble(),
    collectionRate: (json['collection_rate'] ?? 0).toDouble(),
    budgetUsage: (json['budget_usage'] as List? ?? []).map((b) => BudgetUsage.fromJson(b)).toList(),
    revenueTrend12m: (json['revenue_trend_12m'] as List? ?? []).map((t) => RevenueTrend.fromJson(t)).toList(),
    pendingInvoices: json['pending_invoices'] ?? 0,
    pendingPayments: json['pending_payments'] ?? 0,
    pendingExpenses: json['pending_expenses'] ?? 0,
  );
}

class BudgetUsage {
  final String name;
  final double total;
  final double used;
  BudgetUsage({required this.name, required this.total, required this.used});
  factory BudgetUsage.fromJson(Map<String, dynamic> json) => BudgetUsage(
    name: json['name'] ?? '', total: (json['total'] ?? 0).toDouble(), used: (json['used'] ?? 0).toDouble());
}

class RevenueTrend {
  final String month;
  final double revenue;
  RevenueTrend({required this.month, required this.revenue});
  factory RevenueTrend.fromJson(Map<String, dynamic> json) => RevenueTrend(
    month: json['month'] ?? '', revenue: (json['revenue'] ?? 0).toDouble());
}
