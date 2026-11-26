import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medivo/features/plan/data/plan_providers.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/medivo_card.dart';
import '../security/audit_controller.dart';
import '../stock/stock_controller.dart';
import '../stock/widgets/stock_style.dart';
import 'widgets/plan_cards.dart';
import 'widgets/plan_tabs.dart';

class PlanPage extends ConsumerWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final stock = ref.watch(stockControllerProvider);
    final data = stock.valueOrNull;
    final plans = ref.watch(plansProvider);
    final selected = ref.watch(selectedPlanProvider);
    final tab = ref.watch(planTabProvider);

    Future<void> reload() async {
      ref.invalidate(plansProvider);
      ref.invalidate(transfersProvider);
      ref.invalidate(outcomesProvider);
      ref.invalidate(auditControllerProvider);
      try {
        // ignore: unused_result
        await ref.refresh(stockControllerProvider.future);
      } catch (_) {}
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Expiry-aware plan',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'First-expiry-first-out. Expired stock is excluded. Whole packs only. Medicines are never swapped for similar names.',
          style: TextStyle(color: c.muted, height: 1.4),
        ),
        const SizedBox(height: 18),
      ],
    );

    Widget content;
    if (data == null) {
      content = stock.isLoading
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          : MedivoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ErrorBanner('Could not load stock. Check your connection.'),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: reload, child: const Text('Try again')),
                ],
              ),
            );
    } else {
      content = plans.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, __) => MedivoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ErrorBanner('Could not load plans. Check your connection.'),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: reload, child: const Text('Try again')),
            ],
          ),
        ),
        data: (list) {
          final plan = selected.valueOrNull;
          if (plan == null) {
            return MedivoCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No plan yet. Generate one above.',
                      style: TextStyle(color: c.muted)),
                ),
              ),
            );
          }

          Widget tabBody;
          switch (tab) {
            case PlanTab.orders:
              tabBody = OrdersTab(plan: plan, data: data);
            case PlanTab.transfers:
              tabBody = TransfersTab(plan: plan, data: data);
            case PlanTab.recalls:
              tabBody = RecallsTab(data: data);
            case PlanTab.outcomes:
              tabBody = OutcomesTab(plan: plan);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlanPicker(plans: list, selected: plan),
              const SizedBox(height: 14),
              PlanHero(plan: plan),
              const SizedBox(height: 14),
              ApprovalCard(plan: plan),
              const SizedBox(height: 14),
              SegmentedButton<PlanTab>(
                showSelectedIcon: false,
                segments: [
                  for (final t in PlanTab.values) ButtonSegment(value: t, label: Text(t.label)),
                ],
                selected: {tab},
                onSelectionChanged: (s) => ref.read(planTabProvider.notifier).state = s.first,
              ),
              const SizedBox(height: 14),
              tabBody,
            ],
          );
        },
      );
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          header,
          const GenerateCard(),
          const SizedBox(height: 14),
          content,
        ],
      ),
    );
  }
}