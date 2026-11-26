import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/plan/data/plan_models.dart';

Map<String, dynamic> _row({List<dynamic>? moves, List<dynamic>? orders}) => {
      'id': 'p1',
      'state': 'reviewed',
      'version': 3,
      'revision': 0,
      'created_at': '2026-11-24T08:30:00+00:00',
      'reviewed_version': 3,
      'horizon_days': 14,
      'source': 'model',
      'input_hash': 'abc',
      'content_hash': null,
      'risk_before': 1056,
      'risk_after': 576,
      'approved_at': null,
      'moves': moves ?? [],
      'orders': orders ?? [],
    };

void main() {
  test('a plan row is read, and loss kept away is before minus after', () {
    final p = PlanRecord.fromJson(_row());
    expect(p.state, PlanState.reviewed);
    expect(p.version, 3);
    expect(p.saved, 480);
    expect(p.horizon, 14);
  });

  test('older plans with notes instead of moves are read without crashing', () {
    final p = PlanRecord.fromJson(_row(
      moves: [
        {'note': 'demo moves'},
      ],
      orders: [
        {'note': 'demo orders'},
      ],
    ));
    expect(p.moves, isEmpty);
    expect(p.orders, isEmpty);
  });

  test('moves and orders survive a round trip through json', () {
    const move = PlanMove(
      medicineId: 'm',
      batchId: 'b',
      batchCode: 'B-1',
      fromBranchId: 'a',
      toBranchId: 'c',
      quantity: 400,
      daysLeft: 12,
      saved: 480,
    );
    const order = PlanOrder(
      medicineId: 'm',
      branchId: 'a',
      packs: 2,
      units: 200,
      cost: 240,
      orderByDays: 0,
      leadTimeDays: 3,
    );
    final p = PlanRecord.fromJson(_row(moves: [move.toJson()], orders: [order.toJson()]));
    expect(p.moves.single.quantity, 400);
    expect(p.orders.single.packs, 2);
    expect(p.orderTotal, 240);
    expect(move.toTransferJson().keys, containsAll(['medicine_id', 'batch_id', 'quantity']));
  });

  test('unknown states fall back to draft', () {
    expect(PlanState.fromKey('approved'), PlanState.approved);
    expect(PlanState.fromKey('nonsense'), PlanState.draft);
  });

  test('outcomes report the saving in percent', () {
    final o = OutcomeRecord.fromJson({
      'id': 'o1',
      'plan_id': 'p1',
      'cycle_label': 'Cycle 1',
      'baseline_cost': 1000,
      'plan_cost': 750,
      'created_at': '2026-11-24T08:30:00+00:00',
    });
    expect(o.saved, 250);
    expect(o.savedPct, 25);
  });
}