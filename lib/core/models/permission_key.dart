import 'role.dart';

/// The database stores permissions in snake_case (for example `approve_transfer`).
/// This is the one place the app converts its enum names to those keys.
extension PermissionKey on Permission {
  String get key => name.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (m) => '_${m[0]!.toLowerCase()}',
      );
}

extension RoleKey on Role {
  /// Matches the `user_role` enum in the database.
  String get key => switch (this) {
        Role.pharmacist => 'pharmacist',
        Role.purchaser => 'purchaser',
        Role.branchManager => 'branch_manager',
      };
}