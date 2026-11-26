import '../../../core/utils/format.dart';

double _r2(double v) => (v * 100).round() / 100;

enum PlanState {
  draft('draft', 'Draft'),
  reviewed('reviewed', 'Reviewed'),
  approved('approved', 'Approved'),
  returned('returned', 'Returned');

  const PlanState(this.key, this.label);
  final String key;
  final String label;

  static PlanState fromKey(String key) =>
      PlanState.values.firstWhere((s) => s.key == key, orElse: () => PlanState.draft);
}

/// Move stock that would otherwise expire to a branch that will run short.
class PlanMove {
  const PlanMove({
    required this.medicineId,
    required this.batchId,
    required this.batchCode,
    required this.fromBranchId,
    required this.toBranchId,
    required this.quantity,
    required this.daysLeft,
    required this.saved,
  });

  final String medicineId;
  final String batchId;
  final String batchCode;
  final String fromBranchId;
  final String toBranchId;
  final int quantity;
  final int daysLeft;

  /// Value of the stock that is kept from expiring.
  final double saved;

  Map<String, dynamic> toJson() => {
        'medicine_id': medicineId,
        'batch_id': batchId,
        'batch_code': batchCode,
        'from_branch_id': fromBranchId,
        'to_branch_id': toBranchId,
        'quantity': quantity,
        'days_left': daysLeft,
        'saved': _r2(saved),
      };

  /// What the server needs to create the transfer.
  Map<String, dynamic> toTransferJson() => {
        'medicine_id': medicineId,
        'batch_id': batchId,
        'from_branch_id': fromBranchId,
        'to_branch_id': toBranchId,
        'quantity': quantity,
      };

  /// Returns null for anything that is not a move (older plans may hold notes).
  static PlanMove? tryFromJson(dynamic j) {
    if (j is! Map) return null;
    final m = Map<String, dynamic>.from(j);
    try {
      return PlanMove(
        medicineId: m['medicine_id'] as String,
        batchId: m['batch_id'] as String,
        batchCode: m['batch_code'] as String,
        fromBranchId: m['from_branch_id'] as String,
        toBranchId: m['to_branch_id'] as String,
        quantity: (m['quantity'] as num).toInt(),
        daysLeft: (m['days_left'] as num).toInt(),
        saved: (m['saved'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Buy whole packs for a branch that will run short.
class PlanOrder {
  const PlanOrder({
    required this.medicineId,
    required this.branchId,
    required this.packs,
    required this.units,
    required this.cost,
    required this.orderByDays,
    required this.leadTimeDays,
  });

  final String medicineId;
  final String branchId;
  final int packs;
  final int units;
  final double cost;

  /// Days from today. Zero means order now.
  final int orderByDays;
  final int leadTimeDays;

  Map<String, dynamic> toJson() => {
        'medicine_id': medicineId,
        'branch_id': branchId,
        'packs': packs,
        'units': units,
        'cost': _r2(cost),
        'order_by_days': orderByDays,
        'lead_time_days': leadTimeDays,
      };

  static PlanOrder? tryFromJson(dynamic j) {
    if (j is! Map) return null;
    final m = Map<String, dynamic>.from(j);
    try {
      return PlanOrder(
        medicineId: m['medicine_id'] as String,
        branchId: m['branch_id'] as String,
        packs: (m['packs'] as num).toInt(),
        units: (m['units'] as num).toInt(),
        cost: (m['cost'] as num).toDouble(),
        orderByDays: (m['order_by_days'] as num).toInt(),
        leadTimeDays: (m['lead_time_days'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The result of the planner, before it is saved.
class PlanDraft {
  const PlanDraft({
    required this.moves,
    required this.orders,
    required this.riskBefore,
    required this.riskAfter,
    required this.skipped,
  });

  final List<PlanMove> moves;
  final List<PlanOrder> orders;

  /// Value that would expire unsold without the plan.
  final double riskBefore;

  /// Value that would still expire after the transfers.
  final double riskAfter;

  /// Medicine and branch pairs left out because there was not enough sales history.
  final List<String> skipped;

  double get saved => moves.fold(0.0, (a, m) => a + m.saved);

  List<Map<String, dynamic>> get movesJson => [for (final m in moves) m.toJson()];
  List<Map<String, dynamic>> get ordersJson => [for (final o in orders) o.toJson()];
  List<Map<String, dynamic>> get transfersJson => [for (final m in moves) m.toTransferJson()];
}

List<PlanMove> _moves(dynamic raw) => [
      for (final e in (raw as List? ?? const []))
        if (PlanMove.tryFromJson(e) != null) PlanMove.tryFromJson(e)!,
    ];

List<PlanOrder> _orders(dynamic raw) => [
      for (final e in (raw as List? ?? const []))
        if (PlanOrder.tryFromJson(e) != null) PlanOrder.tryFromJson(e)!,
    ];

/// A saved plan, as read from the database.
class PlanRecord {
  const PlanRecord({
    required this.id,
    required this.state,
    required this.version,
    required this.revision,
    required this.createdAt,
    this.reviewedVersion,
    this.horizon,
    this.source,
    this.inputHash,
    this.contentHash,
    this.riskBefore,
    this.riskAfter,
    this.approvedAt,
    this.moves = const [],
    this.orders = const [],
  });

  factory PlanRecord.fromJson(Map<String, dynamic> j) => PlanRecord(
        id: j['id'] as String,
        state: PlanState.fromKey(j['state'] as String),
        version: (j['version'] as num).toInt(),
        revision: (j['revision'] as num).toInt(),
        createdAt: DateTime.parse(j['created_at'] as String),
        reviewedVersion: (j['reviewed_version'] as num?)?.toInt(),
        horizon: (j['horizon_days'] as num?)?.toInt(),
        source: j['source'] as String?,
        inputHash: j['input_hash'] as String?,
        contentHash: j['content_hash'] as String?,
        riskBefore: (j['risk_before'] as num?)?.toDouble(),
        riskAfter: (j['risk_after'] as num?)?.toDouble(),
        approvedAt: j['approved_at'] == null ? null : DateTime.parse(j['approved_at'] as String),
        moves: _moves(j['moves']),
        orders: _orders(j['orders']),
      );

  final String id;
  final PlanState state;
  final int version;
  final int revision;
  final DateTime createdAt;
  final int? reviewedVersion;
  final int? horizon;
  final String? source;
  final String? inputHash;
  final String? contentHash;
  final double? riskBefore;
  final double? riskAfter;
  final DateTime? approvedAt;
  final List<PlanMove> moves;
  final List<PlanOrder> orders;

  /// Expiry loss kept away by the transfers.
  double get saved {
    final b = riskBefore;
    final a = riskAfter;
    if (b != null && a != null) return b - a;
    return moves.fold(0.0, (s, m) => s + m.saved);
  }

  double get orderTotal => orders.fold(0.0, (s, o) => s + o.cost);

  String get label => '${formatDateTime(createdAt)} · ${state.label}';
}

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.planId,
    required this.medicineId,
    required this.batchId,
    required this.fromBranchId,
    required this.toBranchId,
    required this.quantity,
    required this.state,
  });

  factory TransferRecord.fromJson(Map<String, dynamic> j) => TransferRecord(
        id: j['id'] as String,
        planId: j['plan_id'] as String,
        medicineId: j['medicine_id'] as String,
        batchId: j['batch_id'] as String,
        fromBranchId: j['from_branch_id'] as String,
        toBranchId: j['to_branch_id'] as String,
        quantity: (j['quantity'] as num).toInt(),
        state: j['state'] as String,
      );

  final String id;
  final String planId;
  final String medicineId;
  final String batchId;
  final String fromBranchId;
  final String toBranchId;
  final int quantity;

  /// pending, approved or rejected.
  final String state;
}

class OutcomeRecord {
  const OutcomeRecord({
    required this.id,
    required this.planId,
    required this.label,
    required this.baseline,
    required this.plan,
    required this.createdAt,
  });

  factory OutcomeRecord.fromJson(Map<String, dynamic> j) => OutcomeRecord(
        id: j['id'] as String,
        planId: j['plan_id'] as String,
        label: j['cycle_label'] as String,
        baseline: (j['baseline_cost'] as num).toDouble(),
        plan: (j['plan_cost'] as num).toDouble(),
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  final String id;
  final String planId;
  final String label;

  /// Expiry loss without the plan.
  final double baseline;

  /// Expiry loss with the plan.
  final double plan;
  final DateTime createdAt;

  double get saved => baseline - plan;
  int get savedPct => baseline <= 0 ? 0 : ((1 - plan / baseline) * 100).round();
}