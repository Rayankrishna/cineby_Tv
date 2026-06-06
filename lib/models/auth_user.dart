class AuthUser {
  final String id;
  final String name;
  final String email;

  const AuthUser({required this.id, required this.name, required this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        name: (json['name'] ?? '') as String,
        email: (json['email'] ?? '') as String,
      );
}
