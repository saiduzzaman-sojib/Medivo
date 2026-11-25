import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/utils/format.dart';

void main() {
  test('compact taka for chart axes', () {
    expect(compactTaka(0), '৳0');
    expect(compactTaka(950), '৳950');
    expect(compactTaka(1000), '৳1k');
    expect(compactTaka(1500), '৳1.5k');
    expect(compactTaka(250000), '৳2.5L');
    expect(compactTaka(12000000), '৳1.2Cr');
  });

  test('short dates for chart labels', () {
    expect(shortDate(DateTime.utc(2026, 11, 5)), '5 Nov');
  });
}