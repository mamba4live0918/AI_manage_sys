class User {
  final String id;
  final String username;
  final String email;
  final String role;
  final String department;
  final String? departmentId;
  final List<String> accessibleModules;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.department,
    this.departmentId,
    this.accessibleModules = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] ?? '',
        username: json['username'] ?? '',
        email: json['email'] ?? '',
        role: json['role'] ?? 'general',
        department: json['department'] ?? '',
        departmentId: json['department_id'],
        accessibleModules: List<String>.from(json['accessible_modules'] ?? []),
      );

  bool get isAdmin => role == 'admin';
}
