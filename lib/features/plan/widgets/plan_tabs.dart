import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medivo/features/plan/data/plan_providers.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/models/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/expiry.dart';
import '../../../core/utils/format.dart' hide shortHash;
import '../../../shared/widgets/medivo_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../overview/widgets/charts.dart';
import '../../overview/widgets/overview_cards.dart';
import '../../stock/data/stock_models.dart';
import '../../stock/widgets/stock_style.dart';
import '../data/plan_models.dart';

import 'plan_sheets.dart';

Widget _empty(MedivoColors c, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.muted))),
    );

// ----------------------------------------------------------------- orders

class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key, required this.plan, required this.data});

  final PlanRecord plan;
  final StockData data;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final meds = {for (final m in data.medicines) m.id: m};
    final branches = {for (final b in data.branches) b.id: b.name};

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle('Suggested orders', subtitle: 'Whole packs only, ordered early enough for the lead time.'),
          const SizedBox(height: 6),
          if (plan.orders.isEmpty) _empty(c, 'No shortages in this plan.'),
          for (final o in plan.orders)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meds[o.medicineId]?.name ?? 'Unknown medicine',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          '${branches[o.branchId] ?? 'Unknown branch'} · pack of ${meds[o.medicineId]?.packSize ?? '?'} · lead time ${o.leadTimeDays} days',
                          style: TextStyle(color: c.muted, fontSize: 12.5),
                        ),
                        const SizedBox(height: 4),
                        StatusChip(
                          label: o.orderByDays == 0
                              ? 'Order now'
                              : 'Order by ${formatDate(DateTime.now().add(Duration(days: o.orderByDays)))}',
                          color: o.orderByDays == 0 ? c.danger : c.secondary,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${o.packs} pack${o.packs == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(formatTaka(o.cost), style: TextStyle(color: c.muted, fontSize: 12.5)),
                    ],
                  ),
                ],
              ),
            ),
          if (plan.orders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))),
                  Text(formatTaka(plan.orderTotal), style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          if (plan.inputHash != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Source: ${plan.horizon}-day ${plan.source} forecast, inputs ${shortHash(plan.inputHash!)}. Similar medicine names are never treated as substitutes.',
                style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- transfers

class TransfersTab extends ConsumerWidget {
  const TransfersTab({super.key, required this.plan, required this.data});

  final PlanRecord plan;
  final StockData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    final canDecide = user?.can(Permission.approveTransfer) ?? false;
    final async = ref.watch(transfersProvider(plan.id));
    final meds = {for (final m in data.medicines) m.id: m};
    final branches = {for (final b in data.branches) b.id: b.name};
    final batches = {for (final i in data.items) i.id: i.batchCode};

    Future<void> decide(TransferRecord t, bool approve) async {
      final messenger = ScaffoldMessenger.of(context);
      final r = await safeRpc(() => ref.read(planRepositoryProvider).decideTransfer(t.id, approve));
      refreshPlanData(ref);
      messenger.showSnackBar(SnackBar(
        content: Text(r.ok ? (approve ? 'Transfer approved' : 'Transfer rejected') : r.userMessage),
      ));
    }

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle('Transfer proposals', subtitle: 'Only a branch manager approves or rejects a transfer.'),
          const SizedBox(height: 6),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const ErrorBanner('Could not load transfers.'),
            data: (list) {
              if (list.isEmpty) return _empty(c, 'No transfers are needed in this plan.');
              return Column(
                children: [
                  for (final t in list)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t.quantity} × ${meds[t.medicineId]?.name ?? 'Unknown medicine'}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  '${branches[t.fromBranchId] ?? '?'} → ${branches[t.toBranchId] ?? '?'} · batch ${batches[t.batchId] ?? '?'}'
                                  '${meds[t.medicineId] == null ? '' : ' · saves ${formatTaka(t.quantity * meds[t.medicineId]!.unitPrice)}'}',
                                  style: TextStyle(color: c.muted, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (t.state != 'pending')
                            StatusChip(
                              label: t.state == 'approved' ? 'Approved' : 'Rejected',
                              color: t.state == 'approved' ? c.primary : c.danger,
                            )
                          else if (canDecide)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                  onPressed: () => decide(t, false),
                                  child: const Text('Reject'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                  onPressed: () => decide(t, true),
                                  child: const Text('Approve'),
                                ),
                              ],
                            )
                          else
                            StatusChip(label: 'Pending · manager only', color: c.warning),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- recalls

class RecallsTab extends ConsumerWidget {
  const RecallsTab({super.key, required this.data});

  final StockData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    final canRecall = user?.can(Permission.approveRecall) ?? false;

    final live = [
      for (final i in data.items)
        if (!i.recalled && i.daysLeft() > 0) i,
    ]..sort((a, b) => a.daysLeft().compareTo(b.daysLeft()));
    final recalled = [for (final i in data.items) if (i.recalled) i];

    Widget tile(StockItem i, Widget trailing) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i.medicine.name} · ${i.batchCode}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${i.branch.name} · ${i.quantity} units · ${expiryLabel(i.daysLeft())}',
                        style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        );

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Recalls',
            subtitle: 'A recall needs a branch manager, a reason and a fresh verification code.',
          ),
          const SizedBox(height: 6),
          if (live.isEmpty && recalled.isEmpty) _empty(c, 'No batches to show.'),
          for (final i in live.take(40))
            tile(
              i,
              canRecall
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        foregroundColor: c.danger,
                        side: BorderSide(color: c.danger.withValues(alpha: 0.6)),
                      ),
                      onPressed: () => showRecallSheet(context, i),
                      child: const Text('Recall'),
                    )
                  : StatusChip(label: 'Manager only', color: c.muted),
            ),
          for (final i in recalled) tile(i, StatusChip(label: 'Recalled', color: c.danger)),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- outcomes

class OutcomesTab extends ConsumerWidget {
  const OutcomesTab({super.key, required this.plan});

  final PlanRecord plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    final canRecord = user?.can(Permission.recordOutcome) ?? false;
    final async = ref.watch(outcomesProvider);

    return async.when(
      loading: () => const MedivoCard(
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      ),
      error: (_, __) => const MedivoCard(child: ErrorBanner('Could not load outcomes.')),
      data: (list) {
        final maxCost = list.fold<double>(1, (m, o) => o.baseline > m ? o.baseline : m);
        final total = list.fold<double>(0, (s, o) => s + o.saved);
        final recorded = list.any((o) => o.planId == plan.id);
        final canRecordNow = canRecord && plan.state == PlanState.approved && !recorded;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MedivoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CardTitle(
                    'Realized planning cost',
                    subtitle: 'Expiry loss without the plan compared with the approved plan, cycle by cycle.',
                  ),
                  const SizedBox(height: 14),
                  if (list.isEmpty) _empty(c, 'No outcomes recorded yet.'),
                  for (final o in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                              StatusChip(label: '−${o.savedPct}%', color: c.primary),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: LinearProgressIndicator(
                              value: o.baseline / maxCost,
                              minHeight: 9,
                              color: c.danger,
                              backgroundColor: c.raised,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: LinearProgressIndicator(
                              value: o.plan / maxCost,
                              minHeight: 9,
                              color: c.primary,
                              backgroundColor: c.raised,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('${formatTaka(o.baseline)} → ${formatTaka(o.plan)}',
                              style: TextStyle(color: c.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  if (list.isNotEmpty)
                    Wrap(
                      spacing: 14,
                      children: [
                        LegendDot(color: c.danger, label: 'Without the plan'),
                        LegendDot(color: c.primary, label: 'With the plan'),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            MedivoCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatTaka(total),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                        Text('saved across ${list.length} cycle${list.length == 1 ? '' : 's'}',
                            style: TextStyle(color: c.muted)),
                      ],
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: canRecordNow ? () => showOutcomeSheet(context, plan, list.length + 1) : null,
                    child: Text(recorded ? 'Recorded' : 'Record outcome'),
                  ),
                ],
              ),
            ),
            if (!canRecordNow && !recorded)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  plan.state != PlanState.approved
                      ? 'An outcome can be recorded once the plan is approved.'
                      : 'Only a pharmacist records outcomes.',
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                ),
              ),
          ],
        );
      },
    );
  }
}