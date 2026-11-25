import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/overview/data/overview_calc.dart';
import 'package:medivo/features/stock/data/stock_models.dart';

final _today = DateTime.utc(2026, 11, 24);
const _branch = Branch(id: 'b1', name: 'Uttara');

Medicine _med(String id, String name, double price) => Medicine(
      id: id,
      productCode: id.toUpperCase(),
      name: name,
      packSize: 10,
      unitPrice: price,
      leadTimeDays: 3,
    );

StockItem _item(
  String code,
  int days, {
  Medicine? med,
  int qty = 100,
  bool recalled = false,
  bool validated = false,
}) =>
    StockItem(
      id: code,
      batchCode: code,
      quantity: qty,
      expiresOn: _today.add(Duration(days: days)),
      validated: validated,
      recalled: recalled,
      medicine: med ?? _med('m1', 'Napa 500mg', 1),
      branch: _branch,
    );

void main() {
  test('buckets follow the 30 and 90 day rules', () {
    expect(bucketOf(-1), Bucket.expired);
    expect(bucketOf(0), Bucket.expired);
    expect(bucketOf(1), Bucket.critical);
    expect(bucketOf(30), Bucket.critical);
    expect(bucketOf(31), Bucket.warning);
    expect(bucketOf(90), Bucket.warning);
    expect(bucketOf(91), Bucket.ok);
  });

  test('bucket values add up by window and skip recalled stock', () {
    final b = bucketValues([
      _item('A', 10),
      _item('B', 60, qty: 200),
      _item('C', -5, qty: 50),
      _item('D', 10, recalled: true),
    ], today: _today);
    expect(b.of(Bucket.critical), 100);
    expect(b.of(Bucket.warning), 200);
    expect(b.of(Bucket.expired), 50);
    expect(b.total, 350);
    expect(b.share(Bucket.warning), closeTo(200 / 350, 0.0001));
  });

  test('kpis separate usable, at-risk, expired and unvalidated stock', () {
    final k = computeKpis([
      _item('A', 10), // critical, not validated
      _item('B', 60, validated: true), // warning
      _item('C', 200, validated: true), // ok
      _item('D', -2), // expired
      _item('E', 5, recalled: true), // ignored
    ], today: _today);
    expect(k.stockValue, 300);
    expect(k.atRiskValue, 200);
    expect(k.atRiskCount, 2);
    expect(k.soonValue, 100);
    expect(k.soonCount, 1);
    expect(k.expiredValue, 100);
    expect(k.expiredCount, 1);
    expect(k.needValidation, 1);
  });

  test('risk by medicine is sorted by total value', () {
    final napa = _med('m1', 'Napa 500mg', 1);
    final ace = _med('m2', 'Ace 100ml', 10);
    final r = riskByMedicine([
      _item('A', -3, med: napa),
      _item('B', 20, med: napa),
      _item('C', 20, med: ace),
      _item('D', 300, med: ace),
    ], today: _today);
    expect(r.first.medicine.name, 'Ace 100ml');
    expect(r.first.soon, 1000);
    expect(r.last.expired, 100);
    expect(r.last.soon, 100);
  });

  test('top expiring lists only the next 30 days, biggest value first', () {
    final t = topExpiring([
      _item('SMALL', 5, qty: 10),
      _item('BIG', 20, qty: 500),
      _item('LATER', 60, qty: 900),
      _item('GONE', -1, qty: 900),
    ], today: _today);
    expect([for (final i in t) i.batchCode], ['BIG', 'SMALL']);
  });

  test('demand series keeps promotion days, marks stockouts and ignores returns', () {
    final series = buildDemandSeries(
      [
        {'day': '2026-11-23', 'quantity': 40, 'flag': 'routine'},
        {'day': '2026-11-22', 'quantity': 80, 'flag': 'promotion'},
        {'day': '2026-11-21', 'quantity': 0, 'flag': 'stockout'},
        {'day': '2026-11-23', 'quantity': 6, 'flag': 'return'},
      ],
      today: _today,
      days: 4,
    );
    expect(series.length, 4);
    expect(series[0].quantity, isNull); // 20 Nov: nothing recorded
    expect(series[1].stockout, isTrue); // 21 Nov
    expect(series[1].quantity, isNull);
    expect(series[2].promotion, isTrue); // 22 Nov
    expect(series[2].quantity, 80);
    expect(series[3].quantity, 40); // 23 Nov, the return is not added
  });
}