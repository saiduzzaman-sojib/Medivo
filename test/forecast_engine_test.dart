import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/forecast/data/forecast_engine.dart';
import 'package:medivo/features/forecast/data/forecast_models.dart';

final _start = DateTime.utc(2026, 9, 1);

List<HistoryDay> _history(
  List<int?> q, {
  Set<int> promo = const {},
  Map<int, int> returns = const {},
}) =>
    [
      for (var i = 0; i < q.length; i++)
        HistoryDay(
          day: _start.add(Duration(days: i)),
          quantity: q[i],
          promotion: promo.contains(i),
          stockout: q[i] == null,
          returns: returns[i] ?? 0,
        ),
    ];

// A weekly pattern with a steady upward trend.
final _trend = _history([for (var i = 0; i < 60; i++) 50 + (i % 7) * 5 + i]);

void main() {
  test('cleaning removes promotions, adds returns back and fills stockouts', () {
    final h = _history(
      [10, 12, 14, 16, 18, 20, 22, 30, null, 5],
      promo: {7},
      returns: {9: 3},
    );
    expect(cleanSeries(h), [10, 12, 14, 16, 18, 20, 22, 10, 12, 8]);
  });

  test('history is built from sales rows and ends yesterday', () {
    final h = buildHistory(
      [
        {'day': '2026-11-23', 'quantity': 40, 'flag': 'routine'},
        {'day': '2026-11-23', 'quantity': 6, 'flag': 'return'},
        {'day': '2026-11-22', 'quantity': 80, 'flag': 'promotion'},
        {'day': '2026-11-21', 'quantity': 0, 'flag': 'stockout'},
      ],
      today: DateTime.utc(2026, 11, 24),
      days: 3,
    );
    expect(h.length, 3);
    expect(h[0].quantity, isNull);
    expect(h[0].stockout, isTrue);
    expect(h[1].quantity, 80);
    expect(h[1].promotion, isTrue);
    expect(h[2].quantity, 40);
    expect(h[2].returns, 6);
  });

  test('back-test metrics match the reference calculation', () {
    final r = computeForecast(
      history: _trend,
      horizon: 3,
      source: ForecastSource.model,
      percent: 0,
      unitPrice: 2.0,
    );
    final m = r.metrics;
    expect(m.mae, closeTo(10.921591, 1e-4));
    expect(m.maeBaseline, closeTo(7.0, 1e-9));
    expect(m.wape, closeTo(0.09295, 1e-4));
    expect(m.bias, closeTo(-10.921591, 1e-4));
    expect(m.coverage, closeTo(0.857143, 1e-4));
    expect(m.cost, closeTo(183.482737, 1e-3));
    expect(m.costBaseline, closeTo(117.6, 1e-6));
    expect(m.improvementPct, closeTo(-56.0227, 0.01));
  });

  test('model forecast and interval match the reference calculation', () {
    final r = computeForecast(
      history: _trend,
      horizon: 3,
      source: ForecastSource.model,
      percent: 0,
      unitPrice: 2.0,
    );
    expect(r.points.length, 3);
    expect(r.points[0].value, closeTo(119.407895, 1e-4));
    expect(r.points[1].value, closeTo(124.153833, 1e-4));
    expect(r.points[2].value, closeTo(128.57258, 1e-4));
    // The interval always contains the forecast and widens over time.
    expect(r.points[0].low, closeTo(119.407895, 1e-4));
    expect(r.points[0].high, closeTo(131.276077, 1e-3));
    expect(r.points[1].high, closeTo(136.496742, 1e-3));
    expect(r.hasInterval, isTrue);
  });

  test('baseline and manual forecasts come from the same weekday last week', () {
    final base = computeForecast(
      history: _trend,
      horizon: 2,
      source: ForecastSource.baseline,
      percent: 0,
      unitPrice: 1,
    );
    expect(base.points[0].value, closeTo(123, 1e-9));
    expect(base.hasInterval, isFalse);

    final manual = computeForecast(
      history: _trend,
      horizon: 2,
      source: ForecastSource.manual,
      percent: 10,
      unitPrice: 1,
    );
    expect(manual.points[0].value, closeTo(135.3, 1e-9));
    expect(manual.points[0].baseline, closeTo(123, 1e-9));
  });

  test('too little history is refused with a clear message', () {
    expect(
      () => computeForecast(
        history: _history([for (var i = 0; i < 20; i++) 10]),
        horizon: 7,
        source: ForecastSource.model,
        percent: 0,
        unitPrice: 1,
      ),
      throwsA(isA<ForecastProblem>()),
    );
  });

  test('the input fingerprint is stable and changes with every input', () {
    String h({
      String med = 'm1',
      int horizon = 14,
      ForecastSource source = ForecastSource.model,
      double percent = 0,
      String why = '',
      List<double> series = const [1, 2, 3],
    }) =>
        forecastInputHash(
          medicineId: med,
          branchId: 'b1',
          horizon: horizon,
          source: source,
          percent: percent,
          assumption: why,
          series: series,
        );

    expect(h(), h());
    expect(h().length, 64);
    expect(h(med: 'm2'), isNot(h()));
    expect(h(horizon: 7), isNot(h()));
    expect(h(source: ForecastSource.baseline), isNot(h()));
    expect(h(series: const [1, 2, 4]), isNot(h()));
    // For non-manual sources the percentage and assumption do not matter.
    expect(h(percent: 20, why: 'x'), h());
    expect(
      h(source: ForecastSource.manual, percent: 10, why: 'a'),
      isNot(h(source: ForecastSource.manual, percent: 10, why: 'b')),
    );
  });
}