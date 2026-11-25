import 'dart:math' as math;

/// A round y-axis step (1, 2, 5, 10, 20, 50 ...), never below 1.
double niceStep(double max) {
  final raw = max / 4;
  if (raw <= 0) return 1;
  final pow10 = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / pow10;
  final step = n <= 1 ? 1 : (n <= 2 ? 2 : (n <= 5 ? 5 : 10));
  return math.max(1.0, step * pow10);
}