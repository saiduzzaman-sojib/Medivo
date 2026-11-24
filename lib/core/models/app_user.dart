import 'permission_key.dart';
import 'role.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.tenantId,
    required this.tenantName,
    required this.permissions,
  });

  /// Builds the user from the database function `my_access()`.
  /// The server decides the role and the permissions, never the app.
  factory AppUser.fromAccess(Map<String, dynamic> m, {required String email}) {
    final role = roleFromKey(m['role'] as String);
    if (role == null) throw const FormatException('Unknown role');
    return AppUser(
      id: m['user_id'] as String,
      name: m['full_name'] as String,
      email: email,
      role: role,
      tenantId: m['tenant_id'] as String,
      tenantName: m['tenant_name'] as String,
      permissions: {for (final p in (m['permissions'] as List)) p as String},
    );
  }

  final String id;
  final String name;
  final String email;
  final Role role;

  /// Every record belongs to exactly one tenant (one pharmacy chain).
  final String tenantId;
  final String tenantName;

  /// Permission keys sent by the server, for example `approve_transfer`.
  final Set<String> permissions;

  bool can(Permission permission) => permissions.contains(permission.key);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first.isEmpty ? '?' : parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}