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