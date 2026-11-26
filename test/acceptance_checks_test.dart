import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/models/permission_key.dart';
import 'package:medivo/core/models/permissions.dart';
import 'package:medivo/core/models/role.dart';
import 'package:medivo/features/security/data/acceptance_checks.dart';
import 'package:medivo/features/security/security_checks.dart';

void main() {
  test('every local check passes on the real code', () {
    final results = <String, CheckOutcome>{
      'dead stock': checkPlannerSkipsDeadStock(),
      'whole packs': checkWholePacks(),
      'stockout': checkStockoutNotZero(),
      'personal data': checkPersonalDataRejected(),
      'oversize': checkOversizeRejected(),
      'fingerprint': checkFingerprint(),
      'export': checkExportClean(),
    };
    for (final e in results.entries) {
      expect(e.value.status, CheckStatus.pass, reason: '${e.key}: ${e.value.detail}');
    }
  });

  test('permissions match when the server sends the same keys', () {
    for (final role in Role.values) {
      final server = {for (final p in rolePermissions[role]!) p.key};
      expect(checkPermissionsMatch(role: role, server: server).status, CheckStatus.pass);
    }
  });

  test('a missing or extra permission is reported as a failure', () {
    final server = {for (final p in rolePermissions[Role.pharmacist]!) p.key}
      ..remove('approve_plan')
      ..add('approve_recall');
    final r = checkPermissionsMatch(role: Role.pharmacist, server: server);
    expect(r.status, CheckStatus.fail);
    expect(r.detail, contains('approve_plan'));
    expect(r.detail, contains('approve_recall'));
  });

  test('the check list has unique ids, local checks first', () {
    final ids = [for (final d in checkDefs) d.id];
    expect(ids.toSet().length, ids.length);
    expect(checkDefs.length, 14);
    final firstServer = checkDefs.indexWhere((d) => d.server);
    expect(checkDefs.skip(firstServer).every((d) => d.server), isTrue);
  });

  test('the summary counts statuses and knows when everything passed', () {
    final items = [
      AcceptanceItem(checkDefs[0], status: CheckStatus.pass, detail: 'ok'),
      AcceptanceItem(checkDefs[1], status: CheckStatus.fail, detail: 'no'),
      AcceptanceItem(checkDefs[2], status: CheckStatus.error, detail: 'offline'),
    ];
    final s = AcceptanceState(items: items, finishedAt: DateTime(2026, 11, 24));
    expect(s.passedCount, 1);
    expect(s.failedCount, 1);
    expect(s.errorCount, 1);
    expect(s.allPassed, isFalse);

    final good = AcceptanceState(
      items: [AcceptanceItem(checkDefs[0], status: CheckStatus.pass)],
      finishedAt: DateTime(2026, 11, 24),
    );
    expect(good.allPassed, isTrue);
    expect(AcceptanceState(items: items).allPassed, isFalse);
  });
}