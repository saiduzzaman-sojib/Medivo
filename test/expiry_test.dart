import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/utils/expiry.dart';

void main() {
  final today = DateTime.utc(2026, 11, 24);

  test('counts whole calendar days', () {
    expect(daysUntil(DateTime.utc(2026, 12, 4), today: today), 10);
    expect(daysUntil(DateTime.utc(2026, 11, 24), today: today), 0);
    expect(daysUntil(DateTime.utc(2026, 11, 21), today: today), -3);
  });

  test('levels follow the 30 and 90 day rules', () {
    expect(expiryLevel(-3), ExpiryLevel.expired);
    expect(expiryLevel(0), ExpiryLevel.expired);
    expect(expiryLevel(12), ExpiryLevel.critical);
    expect(expiryLevel(41), ExpiryLevel.warning);
    expect(expiryLevel(140), ExpiryLevel.ok);
  });

  test('labels and database dates read correctly', () {
    expect(expiryLabel(0), 'Expired');
    expect(expiryLabel(1), '1 day');
    expect(expiryLabel(12), '12 days');
    expect(parseDateOnly('2026-12-10'), DateTime.utc(2026, 12, 10));
  });
}