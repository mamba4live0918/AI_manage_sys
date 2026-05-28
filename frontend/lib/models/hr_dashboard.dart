class HrDashboardData {
  final int totalEmployees;
  final int activeEmployees;
  final int newHiresThisMonth;
  final List<DeptCount> employeesByDepartment;
  final List<StatusCount> employeesByStatus;
  final int pendingResumes;
  final int newResumesToday;
  final List<StatusCount> resumesByStatus;
  final int pendingApprovals;
  final List<TypeCount> approvalsByType;
  final int todayInterviews;
  final int weekInterviews;
  final List<UpcomingInterview> upcomingInterviews;
  final List<Activity> recentActivities;

  HrDashboardData({
    required this.totalEmployees,
    required this.activeEmployees,
    required this.newHiresThisMonth,
    required this.employeesByDepartment,
    required this.employeesByStatus,
    required this.pendingResumes,
    required this.newResumesToday,
    required this.resumesByStatus,
    required this.pendingApprovals,
    required this.approvalsByType,
    required this.todayInterviews,
    required this.weekInterviews,
    required this.upcomingInterviews,
    required this.recentActivities,
  });

  factory HrDashboardData.fromJson(Map<String, dynamic> json) {
    return HrDashboardData(
      totalEmployees: json['total_employees'] ?? 0,
      activeEmployees: json['active_employees'] ?? 0,
      newHiresThisMonth: json['new_hires_this_month'] ?? 0,
      employeesByDepartment: (json['employees_by_department'] as List<dynamic>?)
              ?.map((e) => DeptCount.fromJson(e))
              .toList() ?? [],
      employeesByStatus: (json['employees_by_status'] as List<dynamic>?)
              ?.map((e) => StatusCount.fromJson(e))
              .toList() ?? [],
      pendingResumes: json['pending_resumes'] ?? 0,
      newResumesToday: json['new_resumes_today'] ?? 0,
      resumesByStatus: (json['resumes_by_status'] as List<dynamic>?)
              ?.map((e) => StatusCount.fromJson(e))
              .toList() ?? [],
      pendingApprovals: json['pending_approvals'] ?? 0,
      approvalsByType: (json['approvals_by_type'] as List<dynamic>?)
              ?.map((e) => TypeCount.fromJson(e))
              .toList() ?? [],
      todayInterviews: json['today_interviews'] ?? 0,
      weekInterviews: json['week_interviews'] ?? 0,
      upcomingInterviews: (json['upcoming_interviews'] as List<dynamic>?)
              ?.map((e) => UpcomingInterview.fromJson(e))
              .toList() ?? [],
      recentActivities: (json['recent_activities'] as List<dynamic>?)
              ?.map((e) => Activity.fromJson(e))
              .toList() ?? [],
    );
  }
}

class DeptCount {
  final String department;
  final int count;
  DeptCount({required this.department, required this.count});
  factory DeptCount.fromJson(Map<String, dynamic> json) =>
      DeptCount(department: json['department'] ?? '', count: json['count'] ?? 0);
}

class StatusCount {
  final String status;
  final int count;
  StatusCount({required this.status, required this.count});
  factory StatusCount.fromJson(Map<String, dynamic> json) =>
      StatusCount(status: json['status'] ?? '', count: json['count'] ?? 0);
}

class TypeCount {
  final String type;
  final int count;
  TypeCount({required this.type, required this.count});
  factory TypeCount.fromJson(Map<String, dynamic> json) =>
      TypeCount(type: json['type'] ?? '', count: json['count'] ?? 0);
}

class UpcomingInterview {
  final String candidateName;
  final String position;
  final String? scheduledAt;
  UpcomingInterview({required this.candidateName, required this.position, this.scheduledAt});
  factory UpcomingInterview.fromJson(Map<String, dynamic> json) =>
      UpcomingInterview(
        candidateName: json['candidate_name'] ?? '',
        position: json['position'] ?? '',
        scheduledAt: json['scheduled_at'],
      );
}

class Activity {
  final String username;
  final String action;
  final String resourceName;
  final String? createdAt;
  Activity({required this.username, required this.action, required this.resourceName, this.createdAt});
  factory Activity.fromJson(Map<String, dynamic> json) =>
      Activity(
        username: json['username'] ?? '',
        action: json['action'] ?? '',
        resourceName: json['resource_name'] ?? '',
        createdAt: json['created_at'],
      );
}
