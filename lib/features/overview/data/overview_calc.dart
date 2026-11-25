import '../../../core/utils/expiry.dart';
import '../../../core/utils/format.dart';
import '../../stock/data/stock_models.dart';

enum Bucket {
  expired('Expired'),
  critical('Within 30 days'),
  warning('31 to 90 days'),
  ok('Over 90 days');

  const Bucket(this.label);
  final String label;
}

Bucket bucketOf(int daysLeft) {
  if (daysLeft <= 0) return Bucket.expired;
  if (daysLeft <= 30) return Bucket.critical;
  if (daysLeft <= 90) return Bucket.warning;
  return Bucket.ok;
}

class Buckets {
  const Buckets(this.values);

  final Map<Bucket, double> values;

  double of(Bucket b) => values[b] ?? 0;
  double get total => values.values.fold(0.0, (a, b) => a + b);
  double share(Bucket b) => total == 0 ? 0 : of(b) / total;
}

/// Stock value per expiry bucket. Recalled stock is not part of any bucket.
Buckets bucketValues(Iterable<StockItem> items, {DateTime? today}) {
  final m = {for (final b in Bucket.values) b: 0.0};
  for (final i in items) {
    if (i.recalled) continue;
    final b = bucketOf(i.daysLeft(today));
    m[b] = m[b]! + i.value;
  }
  return Buckets(m);
}

Map<String, Buckets> bucketsByBranch(List<StockItem> items, {DateTime? today}) {
  final byBranch = <String, List<StockItem>>{};
  for (final i in items) {
    byBranch.putIfAbsent(i.branch.name, () => []).add(i);
  }
  final names = byBranch.keys.toList()..sort();
  return {for (final n in names) n: bucketValues(byBranch[n]!, today: today)};
}

class MedicineRisk {
  const MedicineRisk(this.medicine, this.expired, this.soon);

  final Medicine medicine;

  /// Value already expired.
  final double expired;

  /// Value expiring within 90 days.
  final double soon;

  double get total => expired + soon;
}

/// Medicines that have expired or soon-to-expire stock, biggest loss first.
List<MedicineRisk> riskByMedicine(List<StockItem> items, {DateTime? today}) {
  final meds = <String, Medicine>{};
  final expired = <String, double>{};
  final soon = <String, double>{};
  for (final i in items) {
    if (i.recalled) continue;
    final id = i.medicine.id;
    meds[id] = i.medicine;
    final d = i.daysLeft(today);
    if (d <= 0) {
      expired[id] = (expired[id] ?? 0) + i.value;
    } else if (d <= 90) {
      soon[id] = (soon[id] ?? 0) + i.value;
    }
  }
  final out = [
    for (final e in meds.entries)
      MedicineRisk(e.value, expired[e.key] ?? 0, soon[e.key] ?? 0),
  ].where((r) => r.total > 0).toList();
  out.sort((a, b) => b.total.compareTo(a.total));
  return out;
}

class OverviewKpis {
  const OverviewKpis({
    required this.stockValue,
    required this.atRiskValue,
    required this.atRiskCount,
    required this.soonValue,
    required this.soonCount,
    required this.expiredValue,
    required this.expiredCount,
    required this.needValidation,
  });

  /// Usable stock: not expired and not recalled.
  final double stockValue;

  /// Usable stock that expires within 90 days.
  final double atRiskValue;
  final int atRiskCount;

  /// Usable stock that expires within 30 days.
  final double soonValue;
  final int soonCount;
  final double expiredValue;
  final int expiredCount;
  final int needValidation;
}

OverviewKpis computeKpis(List<StockItem> items, {DateTime? today}) {
  var stock = 0.0, atRisk = 0.0, soon = 0.0, expired = 0.0;
  var atRiskCount = 0, soonCount = 0, expiredCount = 0, need = 0;
  for (final i in items) {
    if (i.recalled) continue;
    final d = i.daysLeft(today);
    if (d <= 0) {
      expired += i.value;
      expiredCount++;
      continue;
    }
    stock += i.value;
    if (d <= 90) {
      atRisk += i.value;
      atRiskCount++;
    }
    if (d <= 30) {
      soon += i.value;
      soonCount++;
    }
    if (!i.validated) need++;
  }
  return OverviewKpis(
    stockValue: stock,
    atRiskValue: atRisk,
    atRiskCount: atRiskCount,
    soonValue: soon,
    soonCount: soonCount,
    expiredValue: expired,
    expiredCount: expiredCount,
    needValidation: need,
  );
}

/// The batches closest to expiry that still have value to save.
List<StockItem> topExpiring(List<StockItem> items, {int limit = 4, DateTime? today}) {
  final list = [
    for (final i in items)
      if (!i.recalled && i.daysLeft(today) > 0 && i.daysLeft(today) <= 30) i,
  ];
  list.sort((a, b) => b.value.compareTo(a.value));
  return list.take(limit).toList();
}

/// One day of recorded sales.
class DemandDay {
  const DemandDay({
    required this.day,
    required this.quantity,
    required this.promotion,
    required this.stockout,
  });

  final DateTime day;

  /// Null when nothing is recorded, or when the day was a stockout.
  final int? quantity;
  final bool promotion;

  /// Stock ran out. This is missing demand, never zero demand.
  final bool stockout;
}

/// Turns sales rows into a continuous window ending yesterday.
/// Returns are left out here. Promotion days are marked.
List<DemandDay> buildDemandSeries(
  List<Map<String, dynamic>> rows, {
  required DateTime today,
  int days = 28,
}) {
  final byDay = <String, List<Map<String, dynamic>>>{};
  for (final r in rows) {
    byDay.putIfAbsent(r['day'] as String, () => []).add(r);
  }
  final last = dateOnly(today).subtract(const Duration(days: 1));
  final out = <DemandDay>[];
  for (var k = days - 1; k >= 0; k--) {
    final d = last.subtract(Duration(days: k));
    int? qty;
    var promo = false;
    var stock = false;
    for (final r in byDay[isoDate(d)] ?? const <Map<String, dynamic>>[]) {
      final flag = r['flag'] as String;
      final q = (r['quantity'] as num).toInt();
      if (flag == 'routine' || flag == 'promotion') {
        qty = (qty ?? 0) + q;
        if (flag == 'promotion') promo = true;
      } else if (flag == 'stockout') {
        stock = true;
      }
    }
    out.add(DemandDay(day: d, quantity: qty, promotion: promo, stockout: stock));
  }
  return out;
}