import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medivo/features/plan/data/plan_providers.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/models/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart' hide shortHash;
import '../../../shared/widgets/medivo_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../forecast/data/forecast_models.dart';
import '../../overview/widgets/overview_cards.dart';
import '../../stock/widgets/stock_style.dart';
import '../data/plan_models.dart';
import 'plan_sheets.dart';

class GenerateCard extends ConsumerWidget {
  const GenerateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    final horizon = ref.watch(planHorizonProvider);
    final source = ref.watch(planSourceProvider);
    final gen = ref.watch(generateProvider);
    final canGenerate = user?.can(Permission.runForecast) ?? false;

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Generate a plan',
            subtitle:
                'Forecasts every medicine and branch, sells stock first-expiry-first-out, moves stock that would expire to branches that will run short and orders the rest in whole packs.',
          ),
          const SizedBox(height: 14),
          Text('Horizon', style: TextStyle(color: c.muted, fontSize: 12.5)),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 14, label: Text('14 days')),
              ButtonSegment(value: 21, label: Text('21 days')),
            ],
            selected: {horizon},
            onSelectionChanged: (s) => ref.read(planHorizonProvider.notifier).state = s.first,
          ),
          const SizedBox(height: 14),
          Text('Forecast source', style: TextStyle(color: c.muted, fontSize: 12.5)),
          const SizedBox(height: 6),
          SegmentedButton<ForecastSource>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ForecastSource.model, label: Text('AI model')),
              ButtonSegment(value: ForecastSource.baseline, label: Text('Baseline')),
            ],
            selected: {source},
            onSelectionChanged: (s) => ref.read(planSourceProvider.notifier).state = s.first,
          ),
          const SizedBox(height: 16),
          if (!canGenerate)
            Row(
              children: [
                Icon(Icons.lock_rounded, color: c.muted, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Your role cannot generate plans.')),
              ],
            )
          else
            FilledButton.icon(
              onPressed: gen.working ? null : () => ref.read(generateProvider.notifier).run(),
              icon: gen.working
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: c.muted),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(gen.working ? gen.step : 'Generate plan'),
            ),
          if (gen.error != null) ...[const SizedBox(height: 12), ErrorBanner(gen.error!)],
          if (gen.message != null) ...[
            const SizedBox(height: 12),
            Text(gen.message!, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
          ],
          if (gen.skipped.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Left out because there is not enough sales history: ${gen.skipped.take(4).join(', ')}${gen.skipped.length > 4 ? ' and ${gen.skipped.length - 4} more' : ''}. Import more sales in the Stock tab.',
              style: TextStyle(color: c.warning, fontSize: 12.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class PlanPicker extends ConsumerWidget {
  const PlanPicker({super.key, required this.plans, required this.selected});

  final List<PlanRecord> plans;
  final PlanRecord selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownMenu<String>(
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      label: const Text('Plan'),
      initialSelection: selected.id,
      dropdownMenuEntries: [
        for (final p in plans) DropdownMenuEntry(value: p.id, label: p.label),
      ],
      onSelected: (id) {
        if (id != null) ref.read(selectedPlanIdProvider.notifier).state = id;
      },
    );
  }
}

class PlanHero extends StatelessWidget {
  const PlanHero({super.key, required this.plan});

  final PlanRecord plan;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        );

    final hasRisk = plan.riskBefore != null && plan.riskAfter != null;
    final meta = [
      if (plan.horizon != null) '${plan.horizon}-day plan',
      if (plan.source != null) plan.source == 'baseline' ? 'baseline forecast' : 'AI model forecast',
      if (plan.inputHash != null) 'fingerprint ${shortHash(plan.inputHash!)}',
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MedivoColors.hero,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Expiry loss kept away by transfers',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(hasRisk ? formatTaka(plan.saved) : '–',
              style: const TextStyle(
                  color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 4),
          Text(meta.isEmpty ? 'Older plan' : meta, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              pill('Without a plan', hasRisk ? formatTaka(plan.riskBefore!) : '–'),
              pill('Still at risk', hasRisk ? formatTaka(plan.riskAfter!) : '–'),
              pill('Orders', formatTaka(plan.orderTotal)),
            ],
          ),
        ],
      ),
    );
  }
}

class ApprovalCard extends ConsumerWidget {
  const ApprovalCard({super.key, required this.plan});

  final PlanRecord plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final canReview = user.can(Permission.reviewPlan);
    final canApprove = user.can(Permission.approvePlan);
    final open = plan.state == PlanState.draft || plan.state == PlanState.reviewed;
    final locked = plan.state == PlanState.approved;

    Future<void> review() async {
      final messenger = ScaffoldMessenger.of(context);
      final r = await safeRpc(() => ref.read(planRepositoryProvider).review(plan.id, plan.version));
      refreshPlanData(ref);
      messenger.showSnackBar(
        SnackBar(content: Text(r.ok ? 'Review submitted for the pharmacist' : r.userMessage)),
      );
    }

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: Text(label, style: TextStyle(color: c.muted))),
              Expanded(
                flex: 6,
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    final chipColor = switch (plan.state) {
      PlanState.approved => c.primary,
      PlanState.reviewed => c.secondary,
      PlanState.returned => c.danger,
      PlanState.draft => c.warning,
    };

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Review and approval',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              StatusChip(
                label: locked ? 'Locked · revision ${plan.revision}' : plan.state.label,
                color: chipColor,
              ),
            ],
          ),
          const SizedBox(height: 6),
          row('Plan version', '${plan.version}'),
          row('Reviewed at version', plan.reviewedVersion == null ? 'Not reviewed' : '${plan.reviewedVersion}'),
          if (plan.contentHash != null) row('Locked hash', shortHash(plan.contentHash!)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              if (locked)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => showExportSheet(context, plan),
                  child: const Text('Export approved'),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: (canReview || canApprove) && open ? () => showReturnSheet(context, plan) : null,
                child: const Text('Return'),
              ),
              if (!locked)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: canReview &&
                          (plan.state == PlanState.draft || plan.state == PlanState.returned)
                      ? review
                      : null,
                  child: Text(canReview ? 'Submit review' : 'Purchaser reviews'),
                ),
              if (!locked)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: canApprove && plan.state == PlanState.reviewed
                      ? () => showApproveSheet(context, plan)
                      : null,
                  child: Text(canApprove ? 'Approve plan' : 'Pharmacist approves'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}