import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../../core/utils/expiry.dart';
import '../../../core/utils/format.dart';
import 'forecast_models.dart';

/// The model needs 28 days of lag plus a 14-day back-test.
const int minHistoryDays = 42;
const int minRecordedDays = 35;
const int backtestDays = 14;

/// Turns sales rows into a continuous window ending yesterday.
List<HistoryDay> buildHistory(
  List<Map<String, dynamic>> rows, {
  required DateTime today,
  int days = 60,
}) {
  final byDay = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    byDay.putIfAbsent(r['day'] as String, () => []).add(r);
  }
  final last = dateOnly(today).subtract(const Duration(days: 1));
  final out = <HistoryDay>[];
  for (var k = days - 1; k >= 0; k--) {
    final d = last.subtract(Duration(days: k));
    int? qty;
    var promo = false;
    var stock = false;
    var ret = 0;
    for (final r in byDay[isoDate(d)] ?? const <Map<String, dynamic>>[]) {
      final flag = r['flag'] as String;
      final q = (r['quantity'] as num).toInt();
      if (flag == 'routine') {
        qty = (qty ?? 0) + q;
      } else if (flag == 'promotion') {
        qty = (qty ?? 0) + q;
        promo = true;
      } else if (flag == 'return') {
        ret += q;
      } else if (flag == 'stockout') {
        stock = true;
      }
    }
    out.add(HistoryDay(
      day: d,
      quantity: qty,
      promotion: promo,
      stockout: stock,
      returns: ret,
    ));
  }
  return out;
}

/// Separates routine demand from promotions, returns and stockouts:
///  - a promotion day takes the value of the same weekday a week earlier
///  - returns are added back to the day they reduced
///  - a stockout or missing day is filled from a week earlier, or the average
List<double> cleanSeries(List<HistoryDay> h) {
  final n = h.length;
  final first = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final d = h[i];
    double? v = d.quantity?.toDouble();
    if (d.promotion && i >= 7) {
      v = h[i - 7].quantity?.toDouble();
    } else if (v != null) {
      v = v + d.returns;
    }
    first[i] = v ?? 0;
  }
  final nonZero = first.where((v) => v > 0).toList();
  final mean = nonZero.isEmpty ? 0.0 : nonZero.reduce((a, b) => a + b) / nonZero.length;
  return [
    for (var i = 0; i < n; i++)
      first[i] > 0 ? first[i] : ((i >= 7 && first[i - 7] > 0) ? first[i - 7] : mean),
  ];
}

double _mean(List<double> a, int from, int to) {
  var s = 0.0;
  for (var i = from; i < to; i++) {
    s += a[i];
  }
  return s / (to - from);
}

/// Seasonal-naive: the same weekday last week.
double naivePred(List<double> a, int i) => a[i - 7];

/// Average of the same weekday over four weeks, scaled by the recent trend.
double modelPred(List<double> a, int i) {
  final seasonal = (a[i - 7] + a[i - 14] + a[i - 21] + a[i - 28]) / 4;
  final trend = (_mean(a, i - 7, i) / math.max(1.0, _mean(a, i - 14, i - 7)))
      .clamp(0.85, 1.15)
      .toDouble();
  return seasonal * trend;
}

double quantile(List<double> values, double q) {
  final s = List<double>.of(values)..sort();
  return s[math.min(s.length - 1, (q * s.length).floor())];
}

class _Backtest {
  const _Backtest(this.metrics, this.lo, this.hi);
  final ForecastMetrics metrics;
  final double lo;
  final double hi;
}

/// Replays the last 14 days using only the data before each day.
_Backtest _backtest(List<double> a, double unitPrice) {
  final n = a.length;
  final residuals = <double>[];
  var ae = 0.0, ab = 0.0, sa = 0.0, bias = 0.0, cost = 0.0, costB = 0.0;
  for (var i = n - backtestDays; i < n; i++) {
    final f = modelPred(a, i);
    final nv = naivePred(a, i);
    final e = a[i] - f;
    residuals.add(e);
    ae += e.abs();
    sa += a[i];
    ab += (a[i] - nv).abs();
    bias += f - a[i];
    cost += a[i] > f ? (a[i] - f) * unitPrice * 0.6 : (f - a[i]) * unitPrice;
    costB += a[i] > nv ? (a[i] - nv) * unitPrice * 0.6 : (nv - a[i]) * unitPrice;
  }
  final lo = quantile(residuals, 0.1);
  final hi = quantile(residuals, 0.9);
  final inside = residuals.where((e) => e >= lo && e <= hi).length;
  const t = backtestDays;
  return _Backtest(
    ForecastMetrics(
      mae: ae / t,
      maeBaseline: ab / t,
      wape: ae / math.max(1.0, sa),
      bias: bias / t,
      coverage: inside / t,
      cost: cost,
      costBaseline: costB,
    ),
    lo,
    hi,
  );
}

ForecastResult computeForecast({
  required List<HistoryDay> history,
  required int horizon,
  required ForecastSource source,
  required double percent,
  required double unitPrice,
}) {
  final recorded = history.where((d) => d.quantity != null).length;
  if (history.length < minHistoryDays || recorded < minRecordedDays) {
    throw const ForecastProblem(
      'Not enough sales history. At least 35 recorded days in the last 60 are needed. Import more sales in the Stock tab.',
    );
  }
  final a = cleanSeries(history);
  final bt = _backtest(a, unitPrice);

  final c = List<double>.of(a);
  final cb = List<double>.of(a);
  final last = history.last.day;
  final points = <ForecastPoint>[];
  for (var k = 0; k < horizon; k++) {
    final v = modelPred(c, c.length);
    c.add(v);
    final nb = naivePred(cb, cb.length);
    cb.add(nb);

    double value;
    double? low;
    double? high;
    switch (source) {
      case ForecastSource.model:
        value = v;
        final widen = 1 + k * 0.04;
        low = math.min(v, math.max(0.0, v + bt.lo * widen));
        high = math.max(v, v + bt.hi * widen);
      case ForecastSource.baseline:
        value = nb;
      case ForecastSource.manual:
        value = nb * (1 + percent / 100);
    }
    points.add(ForecastPoint(
      day: last.add(Duration(days: k + 1)),
      value: value,
      baseline: nb,
      low: low,
      high: high,
    ));
  }

  return ForecastResult(
    source: source,
    points: points,
    metrics: bt.metrics,
    cleaned: a,
    history: history,
    promotionDays: history.where((d) => d.promotion).length,
    stockoutDays: history.where((d) => d.stockout).length,
    returnDays: history.where((d) => d.returns > 0).length,
  );
}

/// A fingerprint of everything that decides the result. The server uses it to
/// recognise the same request, so repeating it never creates a second run.
String forecastInputHash({
  required String medicineId,
  required String branchId,
  required int horizon,
  required ForecastSource source,
  required double percent,
  required String assumption,
  required List<double> series,
}) {
  final manual = source == ForecastSource.manual;
  final parts = [
    medicineId,
    branchId,
    '$horizon',
    source.key,
    manual ? percent.toStringAsFixed(2) : '',
    manual ? assumption.trim() : '',
    series.map((v) => v.toStringAsFixed(4)).join(','),
  ];
  return sha256.convert(utf8.encode(parts.join('|'))).toString();
}