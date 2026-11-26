import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/forecast/data/forecast_models.dart';
import 'package:medivo/features/plan/data/plan_engine.dart';
import 'package:medivo/features/plan/data/plan_models.dart';
import 'package:medivo/features/stock/data/stock_models.dart';

final _today = DateTime.utc(2026, 11, 24);

const _med = Medicine(
  id: 'M1',
  productCode: 'M1',
  name: 'Napa 500mg',
  packSize: 100,
  unitPrice: 1.2,
  leadTimeDays: 3,
);
const _a = Branch(id: 'A', name: 'Branch A');
const _b = Branch(id: 'B', name: 'Branch B');

StockItem _item(String code, Branch br, int days, int qty, {bool recalled = false}) => StockItem(
      id: code,
      batchCode: code,
      quantity: qty,
      expiresOn: _today.add(Duration(days: days)),
      validated: true,
      recalled: recalled,
      medicine: _med,
      branch: br,
    );

PlanDraft _plan(List<StockItem> items, Map<String, List<double>> f) => buildPlan(
      medicines: const [_med],
      branches: const [_a, _b],
      items: items,
      forecasts: f,
      today: _today,
    );

List<double> _flat(double v) => List<double>.filled(14, v);

void main() {
  test('stock that would expire is moved to the branch that runs short', () {
    final p = _plan(
      [_item('A1', _a, 12, 1000), _item('B1', _b, 90, 100), _item('X1', _a, -3, 500)],
      {'M1|A': _flat(10), 'M1|B': _flat(40)},
    );
    expect(p.moves.length, 1);
    final m = p.moves.single;
    expect(m.batchCode, 'A1');
    expect(m.fromBranchId, 'A');
    expect(m.toBranchId, 'B');
    expect(m.quantity, 400);
    expect(m.daysLeft, 12);
    expect(m.saved, closeTo(480, 1e-9));

    expect(p.orders.length, 2);
    final oa = p.orders.firstWhere((o) => o.branchId == 'A');
    final ob = p.orders.firstWhere((o) => o.branchId == 'B');
    expect(oa.packs, 1);
    expect(oa.cost, closeTo(120, 1e-9));
    expect(oa.orderByDays, 9);
    expect(ob.packs, 1);
    expect(ob.orderByDays, 0);

    expect(p.riskBefore, closeTo(1056, 1e-9));
    expect(p.riskAfter, closeTo(576, 1e-9));
    expect(p.saved, closeTo(480, 1e-9));
  });

  test('only whole packs move, so a small shortage is ordered instead', () {
    final p = _plan(
      [_item('A1', _a, 12, 1000), _item('B1', _b, 90, 90)],
      {'M1|A': _flat(10), 'M1|B': _flat(10.4)},
    );
    expect(p.moves, isEmpty);
    expect(p.orders.length, 2);
    expect(p.orders.firstWhere((o) => o.branchId == 'B').orderByDays, 6);
    expect(p.riskBefore, closeTo(1056, 1e-9));
    expect(p.riskAfter, closeTo(1056, 1e-9));
  });

  test('a recalled batch is never planned, expired stock is excluded', () {
    final p = _plan(
      [_item('A1', _a, 12, 1000, recalled: true), _item('B1', _b, 90, 100)],
      {'M1|A': _flat(10), 'M1|B': _flat(40)},
    );
    expect(p.moves, isEmpty);
    expect(p.riskBefore, 0);
    expect(p.orders.firstWhere((o) => o.branchId == 'A').packs, 2);
    expect(p.orders.firstWhere((o) => o.branchId == 'B').packs, 5);
  });

  test('a pair without a forecast is skipped and reported, not guessed', () {
    final p = _plan(
      [_item('A1', _a, 12, 1000), _item('B1', _b, 90, 100)],
      {'M1|A': _flat(10)},
    );
    expect(p.skipped, ['Napa 500mg at Branch B']);
    expect(p.orders.every((o) => o.branchId == 'A'), isTrue);
  });

  test('stock with under 2 days left is not moved', () {
    final p = _plan(
      [_item('A1', _a, 1, 1000), _item('B1', _b, 90, 100)],
      {'M1|A': _flat(0), 'M1|B': _flat(40)},
    );
    expect(p.moves, isEmpty);
  });

  test('the plan fingerprint is stable and changes with the inputs', () {
    final items = [_item('A1', _a, 12, 1000)];
    String h({int horizon = 14, List<StockItem>? stock, double v = 10}) => planInputHash(
          horizon: horizon,
          source: ForecastSource.model,
          forecasts: {'M1|A': _flat(v)},
          items: stock ?? items,
        );
    expect(h(), h());
    expect(h().length, 64);
    expect(h(horizon: 7), isNot(h()));
    expect(h(v: 11), isNot(h()));
    expect(h(stock: [_item('A1', _a, 12, 999)]), isNot(h()));
  });
}