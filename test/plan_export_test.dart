import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/plan/data/plan_export.dart';
import 'package:medivo/features/plan/data/plan_models.dart';

void main() {
  final plan = PlanRecord(
    id: 'p1',
    state: PlanState.approved,
    version: 5,
    revision: 1,
    createdAt: DateTime.utc(2026, 11, 24),
    horizon: 14,
    source: 'model',
    inputHash: 'in-hash',
    contentHash: 'out-hash',
    riskBefore: 1056,
    riskAfter: 576,
    approvedAt: DateTime.utc(2026, 11, 25, 9),
    orders: const [
      PlanOrder(
        medicineId: 'm1',
        branchId: 'a',
        packs: 1,
        units: 100,
        cost: 120,
        orderByDays: 9,
        leadTimeDays: 3,
      ),
    ],
  );

  const transfers = [
    TransferRecord(
        id: 't1', planId: 'p1', medicineId: 'm1', batchId: 'b1',
        fromBranchId: 'a', toBranchId: 'c', quantity: 400, state: 'approved'),
    TransferRecord(
        id: 't2', planId: 'p1', medicineId: 'm1', batchId: 'b1',
        fromBranchId: 'a', toBranchId: 'c', quantity: 100, state: 'rejected'),
    TransferRecord(
        id: 't3', planId: 'p1', medicineId: 'm1', batchId: 'b1',
        fromBranchId: 'a', toBranchId: 'c', quantity: 100, state: 'pending'),
  ];

  test('the export names its inputs, versions and revision', () {
    final j = jsonDecode(buildPlanExport(
      plan: plan,
      transfers: transfers,
      medicineNames: {'m1': 'Napa 500mg'},
      branchNames: {'a': 'Uttara', 'c': 'Mirpur'},
      batchCodes: {'b1': 'B-2291'},
    )) as Map<String, dynamic>;

    expect(j['plan_id'], 'p1');
    expect(j['revision'], 1);
    expect(j['input_hash'], 'in-hash');
    expect(j['content_hash'], 'out-hash');
    expect(j['model_version'], 'lag-quantile-0.3');
    expect(j['policy_version'], 'fefo-pack-1.2');
    expect(j['approved_at'], '2026-11-25T09:00:00.000Z');
    expect((j['orders'] as List).single['medicine'], 'Napa 500mg');
  });

  test('only approved transfers are exported, with readable names', () {
    final j = jsonDecode(buildPlanExport(
      plan: plan,
      transfers: transfers,
      medicineNames: {'m1': 'Napa 500mg'},
      branchNames: {'a': 'Uttara', 'c': 'Mirpur'},
      batchCodes: {'b1': 'B-2291'},
    )) as Map<String, dynamic>;
    final list = j['approved_transfers'] as List;
    expect(list.length, 1);
    expect(list.single['from'], 'Uttara');
    expect(list.single['to'], 'Mirpur');
    expect(list.single['batch'], 'B-2291');
    expect(list.single['quantity'], 400);
  });
}