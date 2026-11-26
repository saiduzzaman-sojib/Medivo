import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../../core/utils/format.dart';
import '../../forecast/data/forecast_models.dart';
import '../../stock/data/stock_models.dart';
import 'plan_models.dart';

class _Lot {
  _Lot(this.item, this.days, this.q);
  final StockItem item;
  final int days;
  int q;
}

/// Stock that will still be on the shelf when its batch expires.
class Leftover {
  const Leftover({required this.item, required this.daysLeft, required this.quantity});
  final StockItem item;
  final int daysLeft;
  final int quantity;
}

class SimResult {
  const SimResult({
    required this.unmet,
    required this.demand,
    required this.firstUnmetDay,
    required this.leftovers,
  });

  /// Demand that cannot be served from the stock on hand.
  final int unmet;
  final int demand;

  /// First day (0 = today) with unmet demand, or -1.
  final int firstUnmetDay;
  final List<Leftover> leftovers;
}

/// Sells the stock day by day, first-expiry-first-out. Expired and recalled
/// batches are left out. A batch cannot be used on or after its expiry day.
SimResult simulateStock(List<StockItem> items, List<double> forecast, {DateTime? today}) {
  final lots = [
    for (final i in items)
      if (!i.recalled && i.daysLeft(today) > 0) _Lot(i, i.daysLeft(today), i.quantity),
  ]..sort((a, b) {
      final c = a.days.compareTo(b.days);
      return c != 0 ? c : a.item.batchCode.compareTo(b.item.batchCode);
    });

  var unmet = 0;
  var demand = 0;
  var firstUnmet = -1;
  for (var d = 0; d < forecast.length; d++) {
    var need = forecast[d].round();
    demand += need;
    for (final lot in lots) {
      if (lot.days <= d) continue;
      final t = math.min(lot.q, need);
      lot.q -= t;
      need -= t;
    }
    unmet += need;
    if (need > 0 && firstUnmet < 0) firstUnmet = d;
  }
  return SimResult(
    unmet: unmet,
    demand: demand,
    firstUnmetDay: firstUnmet,
    leftovers: [
      for (final l in lots)
        if (l.days <= forecast.length && l.q > 0)
          Leftover(item: l.item, daysLeft: l.days, quantity: l.q),
    ],
  );
}

class _Waste {
  _Waste(this.leftover, this.branch) : q = leftover.quantity;
  final Leftover leftover;
  final Branch branch;
  int q;
}

class _Deficit {
  _Deficit(this.branch, this.units, this.firstDay);
  final Branch branch;
  int units;
  final int firstDay;
}

/// Builds orders and transfers for every medicine.
///  - Stock that would expire unsold is moved to a branch that will run short.
///  - Only whole packs move, and only if at least 2 days of shelf life are left.
///  - What is still short is ordered in whole packs, with an order-by day that
///    allows for the lead time.
/// [forecasts] is keyed by "medicineId|branchId". A pair with no forecast is
/// skipped and reported, never guessed.
PlanDraft buildPlan({
  required List<Medicine> medicines,
  required List<Branch> branches,
  required List<StockItem> items,
  required Map<String, List<double>> forecasts,
  DateTime? today,
}) {
  final moves = <PlanMove>[];
  final orders = <PlanOrder>[];
  final skipped = <String>[];
  var before = 0.0;
  var after = 0.0;

  for (final m in medicines) {
    final waste = <_Waste>[];
    final deficits = <_Deficit>[];

    for (final b in branches) {
      final f = forecasts['${m.id}|${b.id}'];
      if (f == null) {
        skipped.add('${m.name} at ${b.name}');
        continue;
      }
      final mine = [
        for (final i in items)
          if (i.medicine.id == m.id && i.branch.id == b.id) i,
      ];
      final s = simulateStock(mine, f, today: today);
      for (final l in s.leftovers) {
        waste.add(_Waste(l, b));
      }
      deficits.add(_Deficit(b, s.unmet, s.firstUnmetDay));
    }

    for (final w in waste) {
      before += w.q * m.unitPrice;
    }

    for (final w in waste) {
      for (final d in deficits) {
        if (d.branch.id == w.branch.id || d.units <= 0 || w.q <= 0 || w.leftover.daysLeft < 2) {
          continue;
        }
        final x = (math.min(w.q, d.units) ~/ m.packSize) * m.packSize;
        if (x >= m.packSize) {
          moves.add(PlanMove(
            medicineId: m.id,
            batchId: w.leftover.item.id,
            batchCode: w.leftover.item.batchCode,
            fromBranchId: w.branch.id,
            toBranchId: d.branch.id,
            quantity: x,
            daysLeft: w.leftover.daysLeft,
            saved: x * m.unitPrice,
          ));
          w.q -= x;
          d.units -= x;
        }
      }
    }

    for (final w in waste) {
      after += w.q * m.unitPrice;
    }

    for (final d in deficits) {
      if (d.units > 0) {
        final packs = (d.units + m.packSize - 1) ~/ m.packSize;
        orders.add(PlanOrder(
          medicineId: m.id,
          branchId: d.branch.id,
          packs: packs,
          units: packs * m.packSize,
          cost: packs * m.packSize * m.unitPrice,
          orderByDays: math.max(0, d.firstDay - m.leadTimeDays),
          leadTimeDays: m.leadTimeDays,
        ));
      }
    }
  }

  return PlanDraft(
    moves: moves,
    orders: orders,
    riskBefore: before,
    riskAfter: after,
    skipped: skipped,
  );
}

/// A fingerprint of everything that decides the plan. The server uses it to
/// recognise the same request, so repeating it never creates a second plan.
String planInputHash({
  required int horizon,
  required ForecastSource source,
  required Map<String, List<double>> forecasts,
  required List<StockItem> items,
}) {
  final keys = forecasts.keys.toList()..sort();
  final f = keys
      .map((k) => '$k:${forecasts[k]!.map((v) => v.toStringAsFixed(2)).join(',')}')
      .join(';');
  final b = [
    for (final i in items) '${i.id}:${i.quantity}:${i.recalled}:${isoDate(i.expiresOn)}',
  ]..sort();
  return sha256
      .convert(utf8.encode('plan-1|$horizon|${source.key}|$f|${b.join(';')}'))
      .toString();
}