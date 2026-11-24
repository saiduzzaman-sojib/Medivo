import '../../../core/network/rpc_result.dart';
import '../../../core/utils/expiry.dart';

class Medicine {
  const Medicine({
    required this.id,
    required this.productCode,
    required this.name,
    required this.packSize,
    required this.unitPrice,
    required this.leadTimeDays,
  });

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id'] as String,
        productCode: j['product_code'] as String,
        name: j['name'] as String,
        packSize: (j['pack_size'] as num).toInt(),
        unitPrice: (j['unit_price'] as num).toDouble(),
        leadTimeDays: (j['lead_time_days'] as num).toInt(),
      );

  final String id;
  final String productCode;
  final String name;
  final int packSize;
  final double unitPrice;
  final int leadTimeDays;
}

class Branch {
  const Branch({required this.id, required this.name});

  factory Branch.fromJson(Map<String, dynamic> j) =>
      Branch(id: j['id'] as String, name: j['name'] as String);

  final String id;
  final String name;
}

class StockItem {
  const StockItem({
    required this.id,
    required this.batchCode,
    required this.quantity,
    required this.expiresOn,
    required this.validated,
    required this.recalled,
    required this.medicine,
    required this.branch,
  });

  /// Returns null when the batch points at a medicine or branch the person cannot see.
  static StockItem? tryParse(
    Map<String, dynamic> j,
    Map<String, Medicine> medicines,
    Map<String, Branch> branches,
  ) {
    final med = medicines[j['medicine_id']];
    final br = branches[j['branch_id']];
    if (med == null || br == null) return null;
    return StockItem(
      id: j['id'] as String,
      batchCode: j['batch_code'] as String,
      quantity: (j['quantity'] as num).toInt(),
      expiresOn: parseDateOnly(j['expires_on'] as String),
      validated: j['validated'] as bool,
      recalled: j['recalled'] as bool,
      medicine: med,
      branch: br,
    );
  }

  final String id;
  final String batchCode;
  final int quantity;
  final DateTime expiresOn;
  final bool validated;
  final bool recalled;
  final Medicine medicine;
  final Branch branch;

  double get value => quantity * medicine.unitPrice;
  int daysLeft([DateTime? today]) => daysUntil(expiresOn, today: today);
  bool isExpired([DateTime? today]) => !recalled && daysLeft(today) <= 0;
}

enum StockFilter {
  all('All'),
  expiringSoon('Expiring in 30 days'),
  expired('Expired'),
  needsValidation('Needs validation'),
  recalled('Recalled');

  const StockFilter(this.label);
  final String label;
}

/// Pure function, so it is easy to test.
List<StockItem> filterItems(
  List<StockItem> items, {
  String query = '',
  StockFilter filter = StockFilter.all,
  DateTime? today,
}) {
  final q = query.trim().toLowerCase();
  bool matches(StockItem i) =>
      q.isEmpty ||
      i.batchCode.toLowerCase().contains(q) ||
      i.medicine.name.toLowerCase().contains(q) ||
      i.medicine.productCode.toLowerCase().contains(q) ||
      i.branch.name.toLowerCase().contains(q);

  bool passes(StockItem i) {
    final days = i.daysLeft(today);
    return switch (filter) {
      StockFilter.all => true,
      StockFilter.expiringSoon => !i.recalled && days > 0 && days <= 30,
      StockFilter.expired => i.isExpired(today),
      StockFilter.needsValidation => !i.validated && !i.recalled && days > 0,
      StockFilter.recalled => i.recalled,
    };
  }

  return [
    for (final i in items)
      if (matches(i) && passes(i)) i,
  ];
}

class StockData {
  const StockData({
    required this.items,
    required this.medicines,
    required this.branches,
  });

  final List<StockItem> items;
  final List<Medicine> medicines;
  final List<Branch> branches;

  int get total => items.length;
  int expiringSoon([DateTime? today]) => filterItems(items, filter: StockFilter.expiringSoon, today: today).length;
  int expired([DateTime? today]) => filterItems(items, filter: StockFilter.expired, today: today).length;
  int needValidation([DateTime? today]) => filterItems(items, filter: StockFilter.needsValidation, today: today).length;
}

class FreshnessEntry {
  const FreshnessEntry({required this.branch, this.daysOld});

  factory FreshnessEntry.fromJson(Map<String, dynamic> j) => FreshnessEntry(
        branch: j['branch'] as String,
        daysOld: (j['days_old'] as num?)?.toInt(),
      );

  final String branch;

  /// Null when the branch has no sales at all.
  final int? daysOld;

  bool get stale => daysOld == null || daysOld! > 3;
}

class ImportError {
  const ImportError(this.row, this.message);
  final int row;
  final String message;
}

class ImportSummary {
  const ImportSummary({
    required this.ok,
    required this.accepted,
    required this.rejected,
    required this.duplicate,
    required this.errors,
    this.message,
  });

  factory ImportSummary.fromResult(RpcResult r) {
    final errors = <ImportError>[];
    for (final e in (r.data['errors'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(e as Map);
      errors.add(ImportError((m['row'] as num).toInt(), m['message'] as String));
    }
    return ImportSummary(
      ok: r.ok,
      accepted: (r.data['accepted'] as num?)?.toInt() ?? 0,
      rejected: (r.data['rejected'] as num?)?.toInt() ?? 0,
      duplicate: r.data['duplicate'] == true,
      errors: errors,
      message: r.ok ? null : r.userMessage,
    );
  }

  final bool ok;
  final int accepted;
  final int rejected;
  final bool duplicate;
  final List<ImportError> errors;
  final String? message;
}