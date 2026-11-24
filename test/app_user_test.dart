import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/models/app_user.dart';
import 'package:medivo/core/models/permission_key.dart';
import 'package:medivo/core/models/role.dart';

Map<String, dynamic> _access(String role, List<String> permissions) => {
      'user_id': '00000000-0000-0000-0000-000000000001',
      'full_name': 'Rahim Uddin',
      'tenant_id': '11111111-1111-1111-1111-111111111111',
      'tenant_name': 'Dhanmondi Pharmacy Chain',
      'role': role,
      'permissions': permissions,
    };

void main() {
  test('builds the user from the my_access response', () {
    final user = AppUser.fromAccess(
      _access('branch_manager', ['approve_transfer', 'view_overview']),
      email: 'manager@medivo.test',
    );
    expect(user.role, Role.branchManager);
    expect(user.initials, 'RU');
    expect(user.can(Permission.approveTransfer), isTrue);
    expect(user.can(Permission.approvePlan), isFalse);
  });

  test('permissions come from the server, not from the role name', () {
    final user = AppUser.fromAccess(
      _access('pharmacist', ['view_overview']),
      email: 'p@medivo.test',
    );
    expect(user.can(Permission.viewOverview), isTrue);
    expect(user.can(Permission.addBatch), isFalse);
  });

  test('an unknown role is rejected', () {
    expect(
      () => AppUser.fromAccess(_access('admin', []), email: 'x@medivo.test'),
      throwsFormatException,
    );
  });

  test('roleFromKey maps database names', () {
    expect(roleFromKey('purchaser'), Role.purchaser);
    expect(roleFromKey('nope'), isNull);
  });
}