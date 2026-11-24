enum ExpiryLevel { expired, critical, warning, ok }

/// Midnight UTC of the given day. Dates are compared as plain calendar days.
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Reads a database date such as "2026-12-10".
DateTime parseDateOnly(String s) {
  final p = s.split('-');
  return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

int daysUntil(DateTime expires, {DateTime? today}) =>
    dateOnly(expires).difference(dateOnly(today ?? DateTime.now())).inDays;

ExpiryLevel expiryLevel(int days) {
  if (days <= 0) return ExpiryLevel.expired;
  if (days <= 30) return ExpiryLevel.critical;
  if (days <= 90) return ExpiryLevel.warning;
  return ExpiryLevel.ok;
}

String expiryLabel(int days) {
  if (days <= 0) return 'Expired';
  return days == 1 ? '1 day' : '$days days';
}