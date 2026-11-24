import 'role.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.tenantId,
    required this.tenantName,
  });

  final String id;
  final String name;
  final String email;
  final Role role;

  /// Every record belongs to exactly one tenant (one pharmacy chain).
  final String tenantId;
  final String tenantName;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first.isEmpty ? '?' : parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}