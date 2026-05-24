class User {
  final String id;
  final String username;
  final String email;
  final String role;
  final String department;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.department,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] ?? '',
        username: json['username'] ?? '',
        email: json['email'] ?? '',
        role: json['role'] ?? 'general',
        department: json['department'] ?? '',
      );

  bool get isAdmin => role == 'admin';
}
