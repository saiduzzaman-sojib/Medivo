import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/stock/data/stock_models.dart';

const _med = Medicine(
  id: 'm1',
  productCode: 'NAPA500',
  name: 'Napa 500mg',
  packSize: 100,
  unitPrice: 1.2,
  leadTimeDays: 3,
);
const _br = Branch(id: 'b1', name: 'Uttara');
final _today = DateTime.utc(2026, 11, 24);

StockItem _item(String code, int days, {bool validated = false, bool recalled = false}) =>
    StockItem(
      id: code,
      batchCode: code,
      quantity: 100,
      expiresOn: _today.add(Duration(days: days)),
      validated: validated,
      recalled: recalled,
      medicine: _med,
      branch: _br,
    );

void main() {
  test('builds an item from a database row, and skips unknown references', () {
    final row = {
      'id': 'x1',
      'batch_code': 'B-1',
      'quantity': 120,
      'expires_on': '2026-12-10',
      'validated': false,
      'recalled': false,
      'medicine_id': 'm1',
      'branch_id': 'b1',
    };
    final item = StockItem.tryParse(row, {'m1': _med}, {'b1': _br});
    expect(item, isNotNull);
    expect(item!.expiresOn, DateTime.utc(2026, 12, 10));
    expect(item.value, closeTo(144, 0.001));
    expect(StockItem.tryParse(row, {}, {'b1': _br}), isNull);
  });

  test('filters by expiry window, expired and validation', () {
    final items = [
      _item('SOON', 12),
      _item('LATER', 140),
      _item('GONE', -3),
      _item('DONE', 12, validated: true),
      _item('RECALLED', 20, recalled: true),
    ];
    List<String> ids(StockFilter f) =>
        [for (final i in filterItems(items, filter: f, today: _today)) i.batchCode];
    expect(ids(StockFilter.expiringSoon), ['SOON', 'DONE']);
    expect(ids(StockFilter.expired), ['GONE']);
    expect(ids(StockFilter.needsValidation), ['SOON', 'LATER']);
    expect(ids(StockFilter.recalled), ['RECALLED']);
    expect(ids(StockFilter.all).length, 5);
  });

  test('search matches batch, medicine and branch', () {
    final items = [_item('B-2291', 12), _item('B-9999', 12)];
    expect(filterItems(items, query: 'b-2291').length, 1);
    expect(filterItems(items, query: 'napa').length, 2);
    expect(filterItems(items, query: 'uttara').length, 2);
    expect(filterItems(items, query: 'nothing').length, 0);
  });

  test('summary counts', () {
    final data = StockData(
      items: [_item('A', 12), _item('B', -3), _item('C', 140, validated: true)],
      medicines: const [_med],
      branches: const [_br],
    );
    expect(data.total, 3);
    expect(data.expiringSoon(_today), 1);
    expect(data.expired(_today), 1);
    expect(data.needValidation(_today), 1);
  });
}