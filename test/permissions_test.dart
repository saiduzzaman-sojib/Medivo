import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/models/permissions.dart';
import 'package:medivo/core/models/role.dart';

void main() {
  test('only the branch manager approves transfers and recalls', () {
    expect(Role.branchManager.can(Permission.approveTransfer), isTrue);
    expect(Role.branchManager.can(Permission.approveRecall), isTrue);
    expect(Role.pharmacist.can(Permission.approveTransfer), isFalse);
    expect(Role.purchaser.can(Permission.approveRecall), isFalse);
  });

  test('purchaser reviews, pharmacist approves the plan', () {
    expect(Role.purchaser.can(Permission.reviewPlan), isTrue);
    expect(Role.purchaser.can(Permission.approvePlan), isFalse);
    expect(Role.pharmacist.can(Permission.approvePlan), isTrue);
    expect(Role.pharmacist.can(Permission.reviewPlan), isFalse);
  });

  test('only the pharmacist validates stock and adds batches', () {
    for (final r in Role.values) {
      expect(r.can(Permission.validateStock), r == Role.pharmacist);
      expect(r.can(Permission.addBatch), r == Role.pharmacist);
    }
  });

  test('everyone can view the overview and the audit log', () {
    for (final r in Role.values) {
      expect(r.can(Permission.viewOverview), isTrue);
      expect(r.can(Permission.viewAudit), isTrue);
    }
  });
}