import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/models/permission_key.dart';
import 'package:medivo/core/models/permissions.dart';
import 'package:medivo/core/models/role.dart';

void main() {
  test('permission keys match the database names', () {
    expect(Permission.approveTransfer.key, 'approve_transfer');
    expect(Permission.viewOverview.key, 'view_overview');
    expect(Permission.manualForecast.key, 'manual_forecast');
  });

  test('role keys match the database enum', () {
    expect(Role.branchManager.key, 'branch_manager');
    expect(Role.pharmacist.key, 'pharmacist');
  });

  test('permission counts per role match the database matrix', () {
    expect(rolePermissions[Role.pharmacist]!.length, 9);
    expect(rolePermissions[Role.purchaser]!.length, 6);
    expect(rolePermissions[Role.branchManager]!.length, 4);
  });
}