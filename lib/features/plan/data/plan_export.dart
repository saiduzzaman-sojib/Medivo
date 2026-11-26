import 'dart:convert';

import 'plan_models.dart';

/// The approved plan as a report. It names the inputs, the model and policy
/// versions and the plan revision, so anyone can tell exactly what was approved.
String buildPlanExport({
  required PlanRecord plan,
  required List<TransferRecord> transfers,
  required Map<String, String> medicineNames,
  required Map<String, String> branchNames,
  required Map<String, String> batchCodes,
}) {
  final map = <String, dynamic>{
    'plan_id': plan.id,
    'revision': plan.revision,
    'state': plan.state.key,
    'content_hash': plan.contentHash,
    'input_hash': plan.inputHash,
    'horizon_days': plan.horizon,
    'source': plan.source,
    'model_version': plan.source == 'baseline' ? 'seasonal-naive-1.0' : 'lag-quantile-0.3',
    'policy_version': 'fefo-pack-1.2',
    'approved_at': plan.approvedAt?.toUtc().toIso8601String(),
    'expiry_loss_without_plan': plan.riskBefore,
    'expiry_loss_with_plan': plan.riskAfter,
    'orders': [
      for (final o in plan.orders)
        {
          'medicine': medicineNames[o.medicineId] ?? o.medicineId,
          'branch': branchNames[o.branchId] ?? o.branchId,
          'packs': o.packs,
          'units': o.units,
          'cost': o.cost,
          'order_by_days': o.orderByDays,
        },
    ],
    'approved_transfers': [
      for (final t in transfers)
        if (t.state == 'approved')
          {
            'medicine': medicineNames[t.medicineId] ?? t.medicineId,
            'batch': batchCodes[t.batchId] ?? t.batchId,
            'from': branchNames[t.fromBranchId] ?? t.fromBranchId,
            'to': branchNames[t.toBranchId] ?? t.toBranchId,
            'quantity': t.quantity,
          },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}