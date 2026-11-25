import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../overview/data/overview_calc.dart';
import '../overview/overview_providers.dart';
import '../overview/widgets/overview_cards.dart';
import '../stock/stock_controller.dart';
import '../stock/widgets/stock_style.dart';
import '../../shared/widgets/medivo_card.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final async = ref.watch(stockControllerProvider);
    final data = async.valueOrNull;
    final freshness = ref.watch(freshnessProvider).valueOrNull ?? const [];

    Future<void> reload() async {
      ref.invalidate(freshnessProvider);
      ref.invalidate(demandSeriesProvider);
      try {
        // ignore: unused_result
        await ref.refresh(stockControllerProvider.future);
      } catch (_) {}
    }

    Widget body;
    if (data == null) {
      body = async.isLoading
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          : MedivoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ErrorBanner('Could not load the overview. Check your connection.'),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: reload, child: const Text('Try again')),
                ],
              ),
            );
    } else {
      final kpis = computeKpis(data.items);
      body = LayoutBuilder(
        builder: (context, cons) {
          final wide = cons.maxWidth >= 900;
          Widget pair(Widget a, Widget b, {int flexA = 3, int flexB = 2}) => wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: flexA, child: a),
                    const SizedBox(width: 14),
                    Expanded(flex: flexB, child: b),
                  ],
                )
              : Column(children: [a, const SizedBox(height: 14), b]);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroCard(kpis: kpis),
              const SizedBox(height: 14),
              StaleWarnings(entries: freshness),
              KpiRow(kpis: kpis),
              const SizedBox(height: 14),
              pair(DemandCard(data: data), HealthCard(data: data)),
              const SizedBox(height: 14),
              pair(ExposureCard(data: data), RiskCard(data: data), flexA: 2, flexB: 3),
              const SizedBox(height: 14),
              AttentionCard(data: data, freshness: freshness),
            ],
          );
        },
      );
    }

    final firstName = user.name.split(' ').first;
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('${formatDate(DateTime.now())} · ${user.tenantName}',
              style: TextStyle(color: c.muted)),
          const SizedBox(height: 2),
          Text('Hello, $firstName',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }
}