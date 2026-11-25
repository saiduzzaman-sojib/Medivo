const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// For example "24 Nov, 14:05" in the phone's local time.
String formatDateTime(DateTime t) {
  final l = t.toLocal();
  return '${l.day} ${_months[l.month - 1]}, ${_two(l.hour)}:${_two(l.minute)}';
}

/// "a1b2c3…9f0e" for long hashes.
String shortHash(String h) =>
    h.length <= 12 ? h : '${h.substring(0, 6)}…${h.substring(h.length - 4)}';

/// "5 min" or "20 sec".
String humanDuration(Duration d) {
  if (d.inSeconds >= 60 && d.inSeconds % 60 == 0) return '${d.inMinutes} min';
  return '${d.inSeconds} sec';
}

/// "batch_added" or "batch added" becomes "Batch added".
String sentenceCase(String s) {
  final t = s.replaceAll('_', ' ').trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}
/// 2026-11-24, the format the database expects.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// "24 Nov 2026" (no time zone shifting, for plain dates).
String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Taka with Bangladeshi digit grouping: ৳12,34,567.
String formatTaka(num value) {
  final n = value.round();
  var s = n.abs().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  return '${n < 0 ? '-' : ''}৳$s';
}
/// "5 Nov" for chart labels.
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// Short money for chart axes: ৳950, ৳1.5k, ৳2.5L (lakh), ৳1.2Cr (crore).
String compactTaka(num v) {
  final a = v.abs();
  String trim(double x) {
    final t = x.toStringAsFixed(1);
    return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
  }

  final String s;
  if (a >= 10000000) {
    s = '${trim(a / 10000000)}Cr';
  } else if (a >= 100000) {
    s = '${trim(a / 100000)}L';
  } else if (a >= 1000) {
    s = '${trim(a / 1000)}k';
  } else {
    s = a.round().toString();
  }
  return '${v < 0 ? '-' : ''}৳$s';
}