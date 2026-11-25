import '../../../core/utils/format.dart';

enum ForecastSource {
  model('model', 'AI model', 'lag-quantile-0.3'),
  baseline('baseline', 'Baseline', 'seasonal-naive-1.0'),
  manual('manual', 'Manual', 'manual-1.0');

  const ForecastSource(this.key, this.label, this.version);
  final String key;
  final String label;
  final String version;
}

double _r4(double v) => (v * 10000).round() / 10000;

/// One day of recorded history.
class HistoryDay {
  const HistoryDay({
    required this.day,
    required this.quantity,
    required this.promotion,
    required this.stockout,
    required this.returns,
  });

  final DateTime day;

  /// Null when nothing was recorded, or the day was a stockout.
  final int? quantity;
  final bool promotion;
  final bool stockout;
  final int returns;
}

class ForecastPoint {
  const ForecastPoint({
    required this.day,
    required this.value,
    required this.baseline,
    this.low,
    this.high,
  });

  final DateTime day;
  final double value;
  final double baseline;
  final double? low;
  final double? high;

  Map<String, dynamic> toJson() => {
        'day': isoDate(day),
        'value': _r4(value),
        'baseline': _r4(baseline),
        'low': low == null ? null : _r4(low!),
        'high': high == null ? null : _r4(high!),
      };
}

class ForecastMetrics {
  const ForecastMetrics({
    required this.mae,
    required this.maeBaseline,
    required this.wape,
    required this.bias,
    required this.coverage,
    required this.cost,
    required this.costBaseline,
  });

  /// Mean absolute error of the model over the back-test, in units per day.
  final double mae;
  final double maeBaseline;

  /// Total absolute error divided by total sales (safe when some days are zero).
  final double wape;

  /// Average of forecast minus actual. Negative means the model under-forecasts.
  final double bias;

  /// Share of back-test days inside the 80% interval.
  final double coverage;

  /// Back-test planning cost: shortages cost 60% of price, surplus 100%.
  final double cost;
  final double costBaseline;

  /// Positive means the model is better than the baseline.
  double? get improvementPct => maeBaseline > 0 ? (1 - mae / maeBaseline) * 100 : null;

  Map<String, dynamic> toJson() => {
        'mae': _r4(mae),
        'mae_baseline': _r4(maeBaseline),
        'wape': _r4(wape),
        'bias': _r4(bias),
        'coverage': _r4(coverage),
        'cost': _r4(cost),
        'cost_baseline': _r4(costBaseline),
      };
}

class ForecastResult {
  const ForecastResult({
    required this.source,
    required this.points,
    required this.metrics,
    required this.cleaned,
    required this.history,
    required this.promotionDays,
    required this.stockoutDays,
    required this.returnDays,
  });

  final ForecastSource source;
  final List<ForecastPoint> points;
  final ForecastMetrics metrics;

  /// The series the model learns from: promotions removed, returns added back,
  /// stockout and missing days filled in.
  final List<double> cleaned;
  final List<HistoryDay> history;
  final int promotionDays;
  final int stockoutDays;
  final int returnDays;

  bool get hasInterval => points.isNotEmpty && points.first.low != null;
}

class ForecastProblem implements Exception {
  const ForecastProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A saved run, as listed under "Recent runs".
class RecentRun {
  const RecentRun({
    required this.id,
    required this.source,
    required this.horizon,
    required this.status,
    required this.modelVersion,
    required this.attempts,
    required this.createdAt,
    this.assumption,
    this.mae,
  });

  factory RecentRun.fromJson(Map<String, dynamic> j) => RecentRun(
        id: j['id'] as String,
        source: j['source'] as String,
        horizon: (j['horizon_days'] as num).toInt(),
        status: j['status'] as String,
        modelVersion: j['model_version'] as String,
        attempts: (j['attempts'] as num).toInt(),
        createdAt: DateTime.parse(j['created_at'] as String),
        assumption: j['assumption'] as String?,
        mae: ((j['metrics'] as Map?)?['mae'] as num?)?.toDouble(),
      );

  final String id;
  final String source;
  final int horizon;
  final String status;
  final String modelVersion;
  final int attempts;
  final DateTime createdAt;
  final String? assumption;
  final double? mae;
}