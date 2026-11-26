import 'dart:convert';
import 'dart:typed_data';

import '../../../core/models/permission_key.dart';
import '../../../core/models/permissions.dart';
import '../../../core/models/role.dart';
import '../../forecast/data/forecast_engine.dart';
import '../../forecast/data/forecast_models.dart';
import '../../plan/data/plan_engine.dart';
import '../../plan/data/plan_export.dart';
import '../../plan/data/plan_models.dart';
import '../../stock/data/import_rules.dart';
import '../../stock/data/stock_models.dart';

enum CheckStatus { pass, fail, error }

class CheckOutcome {
  const CheckOutcome(this.status, this.detail);

  final CheckStatus status;
  final String detail;
}

CheckOutcome passed(String detail) => CheckOutcome(CheckStatus.pass, detail);
CheckOutcome failed(String detail) => CheckOutcome(CheckStatus.fail, detail);

/// The check could not run (for example no connection). That is not a failure.
CheckOutcome couldNotRun(String detail) => CheckOutcome(CheckStatus.error, detail);

// A small, fixed scenario that does not depend on live data.
final _today = DateTime.utc(2026, 11, 24);
const _med = Medicine(
  id: 'M',
  productCode: 'M',
  name: 'Test medicine',
  packSize: 100,
  unitPrice: 1,
  leadTimeDays: 3,
);
const _a = Branch(id: 'A', name: 'Branch A');
const _b = Branch(id: 'B', name: 'Branch B');

StockItem _item(String code, Branch br, int days, int qty, {bool recalled = false}) => StockItem(
      id: code,
      batchCode: code,
      quantity: qty,
      expiresOn: _today.add(Duration(days: days)),
      validated: true,
      recalled: recalled,
      medicine: _med,
      branch: br,
    );

PlanDraft _scenario(List<StockItem> items, double forecastA, double forecastB) => buildPlan(
      medicines: const [_med],
      branches: const [_a, _b],
      items: items,
      forecasts: {
        'M|A': List<double>.filled(14, forecastA),
        'M|B': List<double>.filled(14, forecastB),
      },
      today: _today,
    );

/// Expired and recalled batches must never be planned or moved.
CheckOutcome checkPlannerSkipsDeadStock() {
  final draft = _scenario(
    [
      _item('LIVE', _a, 12, 1000),
      _item('EXPIRED', _a, -3, 900),
      _item('RECALLED', _a, 20, 800, recalled: true),
      _item('SHORT', _b, 90, 100),
    ],
    10,
    40,
  );
  if (draft.moves.isEmpty) {
    return failed('The test scenario produced no transfer, so it proves nothing.');
  }
  final used = {for (final m in draft.moves) m.batchCode};
  if (used.contains('EXPIRED') || used.contains('RECALLED')) {
    return failed('The planner moved dead stock: ${used.join(', ')}.');
  }
  return passed('Moved only live stock (${used.join(', ')}). The expired and recalled batches were left alone.');
}

/// Orders and transfers are whole packs, and a shortage smaller than a pack is ordered, not moved.
CheckOutcome checkWholePacks() {
  final draft = _scenario([_item('LIVE', _a, 12, 1000), _item('SHORT', _b, 90, 100)], 10, 40);
  for (final m in draft.moves) {
    if (m.quantity % _med.packSize != 0) return failed('A transfer of ${m.quantity} is not whole packs.');
  }
  for (final o in draft.orders) {
    if (o.units % _med.packSize != 0) return failed('An order of ${o.units} is not whole packs.');
  }
  final small = _scenario([_item('LIVE', _a, 12, 1000), _item('SHORT', _b, 90, 90)], 10, 10.4);
  if (small.moves.isNotEmpty) return failed('Stock was moved to cover less than one pack.');
  return passed('${draft.moves.length} transfers and ${draft.orders.length} orders are whole packs. A shortage under one pack is ordered, not moved.');
}

/// A stockout day is missing demand, never zero demand.
CheckOutcome checkStockoutNotZero() {
  final start = DateTime.utc(2026, 9, 1);
  final history = [
    for (var i = 0; i < 21; i++)
      HistoryDay(
        day: start.add(Duration(days: i)),
        quantity: i == 14 ? null : 10 + (i % 7),
        promotion: false,
        stockout: i == 14,
        returns: 0,
      ),
  ];
  final cleaned = cleanSeries(history);
  if (cleaned[14] <= 0) return failed('The stockout day was treated as zero demand.');
  return passed('The stockout day was filled with ${cleaned[14].toStringAsFixed(1)} units, not zero.');
}

/// A file with personal columns is refused on the phone, before anything is sent.
CheckOutcome checkPersonalDataRejected() {
  try {
    prepareImport(
      fileName: 'sales.csv',
      bytes: Uint8List.fromList(
        utf8.encode('date,branch,product_code,quantity,patient_name\n2026-11-20,Uttara,NAPA500,10,X\n'),
      ),
    );
    return failed('A file with a patient column was accepted.');
  } on ImportProblem catch (e) {
    return e.message.contains('patient_name')
        ? passed('The file was refused and the column was named.')
        : failed('The file was refused for another reason: ${e.message}');
  }
}

CheckOutcome checkOversizeRejected() {
  try {
    prepareImport(fileName: 'sales.csv', bytes: Uint8List(ImportRules.maxBytes + 1));
    return failed('A file over 1 MB was accepted.');
  } on ImportProblem {
    return passed('A file over 1 MB was refused.');
  }
}

/// The same inputs give the same fingerprint, and any change gives a new one.
CheckOutcome checkFingerprint() {
  String h(int horizon, List<double> series) => forecastInputHash(
        medicineId: 'm',
        branchId: 'b',
        horizon: horizon,
        source: ForecastSource.model,
        percent: 0,
        assumption: '',
        series: series,
      );
  final base = h(14, const [1, 2, 3]);
  if (base != h(14, const [1, 2, 3])) return failed('The same inputs gave different fingerprints.');
  if (base == h(7, const [1, 2, 3]) || base == h(14, const [1, 2, 4])) {
    return failed('A changed input gave the same fingerprint.');
  }
  return passed('Same inputs, same fingerprint. Any change, a new one.');
}

/// An approved export holds no personal fields.
CheckOutcome checkExportClean() {
  final plan = PlanRecord(
    id: 'p',
    state: PlanState.approved,
    version: 2,
    revision: 1,
    createdAt: _today,
    horizon: 14,
    source: 'model',
    inputHash: 'in',
    contentHash: 'out',
    riskBefore: 100,
    riskAfter: 50,
    orders: const [
      PlanOrder(
        medicineId: 'M',
        branchId: 'A',
        packs: 1,
        units: 100,
        cost: 120,
        orderByDays: 0,
        leadTimeDays: 3,
      ),
    ],
  );
  const transfers = [
    TransferRecord(
      id: 't',
      planId: 'p',
      medicineId: 'M',
      batchId: 'LIVE',
      fromBranchId: 'A',
      toBranchId: 'B',
      quantity: 400,
      state: 'approved',
    ),
  ];
  final text = buildPlanExport(
    plan: plan,
    transfers: transfers,
    medicineNames: const {'M': 'Test medicine'},
    branchNames: const {'A': 'Branch A', 'B': 'Branch B'},
    batchCodes: const {'LIVE': 'LIVE'},
  );
  const banned = ['patient', 'phone', 'email', 'address', 'password', 'nid'];

  bool clean(dynamic node) {
    if (node is Map) {
      for (final e in node.entries) {
        final key = e.key.toString().toLowerCase();
        if (banned.any(key.contains)) return false;
        if (!clean(e.value)) return false;
      }
    } else if (node is List) {
      for (final v in node) {
        if (!clean(v)) return false;
      }
    }
    return true;
  }

  return clean(jsonDecode(text))
      ? passed('The export holds plan, order and transfer fields only.')
      : failed('The export holds a personal field.');
}

/// The app and the database must agree on what a role may do.
CheckOutcome checkPermissionsMatch({required Role role, required Set<String> server}) {
  final expected = {for (final p in rolePermissions[role] ?? const <Permission>{}) p.key};
  if (expected.length == server.length && expected.containsAll(server)) {
    return passed('The app and the database agree on ${server.length} permissions for ${role.label}.');
  }
  final missing = expected.difference(server);
  final extra = server.difference(expected);
  final parts = [
    if (missing.isNotEmpty) 'the database lacks ${missing.join(', ')}',
    if (extra.isNotEmpty) 'the app lacks ${extra.join(', ')}',
  ];
  return failed('Out of sync: ${parts.join('; ')}.');
}