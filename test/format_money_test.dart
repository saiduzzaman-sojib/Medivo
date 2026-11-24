import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/utils/format.dart';

void main() {
  test('taka uses Bangladeshi digit grouping', () {
    expect(formatTaka(950), '৳950');
    expect(formatTaka(1000), '৳1,000');
    expect(formatTaka(100000), '৳1,00,000');
    expect(formatTaka(1234567), '৳12,34,567');
    expect(formatTaka(-2500), '-৳2,500');
  });

  test('dates are formatted for people and for the database', () {
    final d = DateTime.utc(2026, 3, 5);
    expect(isoDate(d), '2026-03-05');
    expect(formatDate(d), '5 Mar 2026');
  });
}