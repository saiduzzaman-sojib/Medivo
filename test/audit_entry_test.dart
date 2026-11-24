import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/security/data/audit_entry.dart';

void main() {
  final json = {
    'id': 7,
    'actor_id': '00000000-0000-0000-0000-000000000001',
    'actor_role': 'branch_manager',
    'action': 'transfer approved',
    'ok': true,
    'detail': {'transfer_id': 'abc'},
    'prev_hash': 'a' * 64,
    'row_hash': 'b' * 64,
    'created_at': '2026-11-24T08:30:00+00:00',
  };

  test('builds an entry from the database row', () {
    final e = AuditEntry.fromJson(json);
    expect(e.id, 7);
    expect(e.ok, isTrue);
    expect(e.roleLabel, 'Branch manager');
    expect(e.detail['transfer_id'], 'abc');
  });

  test('a missing role or detail does not crash', () {
    final e = AuditEntry.fromJson({...json, 'actor_role': null, 'detail': null});
    expect(e.roleLabel, 'Unknown role');
    expect(e.detail, isEmpty);
  });
}