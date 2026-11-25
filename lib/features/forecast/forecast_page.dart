import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/medivo_card.dart';
import '../overview/overview_providers.dart';
import '../overview/widgets/overview_cards.dart';
import '../stock/stock_controller.dart';
import '../stock/widgets/stock_style.dart';
import 'data/forecast_models.dart';
import 'forecast_providers.dart';
import 'widgets/forecast_chart.dart';
import 'widgets/forecast_panels.dart';

class ForecastPage extends ConsumerWidget {
  const ForecastPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final stock = ref.watch(stockControllerProvider);
    final data = stock.valueOrNull;

    Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Demand estimates',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Forecast per product and branch. Uses sales up to yesterday.',
            style: TextStyle(color: c.muted)),
        const SizedBox(height: 18),
      ],
    );

    if (data == null || data.medicines.isEmpty || data.branches.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          header,
          if (stock.isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            const MedivoCard(
              child: ErrorBanner('Could not load medicines and branches. Pull down on the Stock tab to retry.'),
            ),
        ],
      );
    }

    final medId = ref.watch(forecastMedicineProvider) ?? data.medicines.first.id;
    final brId = ref.watch(forecastBranchProvider) ?? data.branches.first.id;
    final horizon = ref.watch(forecastHorizonProvider);
    final source = ref.watch(forecastSourceProvider);
    final percent = ref.watch(forecastPercentProvider);
    final kind = ref.watch(forecastKindProvider);
    final medicine = data.medicines.firstWhere((m) => m.id == medId, orElse: () => data.medicines.first);

    final query = (
      medicineId: medicine.id,
      branchId: brId,
      horizon: horizon,
      source: source,
      percent: source == ForecastSource.manual ? percent : 0.0,
      unitPrice: medicine.unitPrice,
    );
    final result = ref.watch(forecastResultProvider(query));
    final key = (medicineId: medicine.id, branchId: brId);

    final canRun = source == ForecastSource.manual
        ? user.can(Permission.manualForecast)
        : user.can(Permission.runForecast);

    final branchName = data.branches.firstWhere((b) => b.id == brId, orElse: () => data.branches.first).name;
    final stale = ref
            .watch(freshnessProvider)
            .valueOrNull
            ?.where((f) => f.branch == branchName && f.stale)
            .firstOrNull;

    Future<void> reload() async {
      ref.invalidate(historyProvider);
      ref.invalidate(recentRunsProvider);
      ref.invalidate(freshnessProvider);
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          header,
          MedivoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    DropdownMenu<String>(
                      width: 220,
                      requestFocusOnTap: false,
                      label: const Text('Medicine'),
                      initialSelection: medicine.id,
                      dropdownMenuEntries: [
                        for (final m in data.medicines) DropdownMenuEntry(value: m.id, label: m.name),
                      ],
                      onSelected: (v) {
                        if (v != null) ref.read(forecastMedicineProvider.notifier).state = v;
                      },
                    ),
                    DropdownMenu<String>(
                      width: 220,
                      requestFocusOnTap: false,
                      label: const Text('Branch'),
                      initialSelection: brId,
                      dropdownMenuEntries: [
                        for (final b in data.branches) DropdownMenuEntry(value: b.id, label: b.name),
                      ],
                      onSelected: (v) {
                        if (v != null) ref.read(forecastBranchProvider.notifier).state = v;
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                  onSelectionChanged: (s) => ref.read(forecastHorizonProvider.notifier).state = s.first,
                ),
                const SizedBox(height: 16),
                Text('Forecast source', style: TextStyle(color: c.muted, fontSize: 12.5)),
                const SizedBox(height: 6),
                SegmentedButton<ForecastSource>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: ForecastSource.model, label: Text('AI model')),
                    const ButtonSegment(value: ForecastSource.baseline, label: Text('Baseline')),
                    ButtonSegment(
                      value: ForecastSource.manual,
                      label: const Text('Manual'),
                      enabled: user.can(Permission.manualForecast),
                    ),
                  ],
                  selected: {source},
                  onSelectionChanged: (s) => ref.read(forecastSourceProvider.notifier).state = s.first,
                ),
                if (source == ForecastSource.baseline) ...[
                  const SizedBox(height: 10),
                  Text('Showing the seasonal baseline: the same weekday last week.',
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                ],
                if (source == ForecastSource.manual) ...[
                  const SizedBox(height: 14),
                  const ManualForm(),
                ],
              ],
            ),
          ),
          if (stale != null) ...[
            const SizedBox(height: 14),
            MedivoCard(
              color: c.warning.withValues(alpha: 0.10),
              padding: const EdgeInsets.all(14),
              child: Text(
                stale.daysOld == null
                    ? '$branchName has no recorded sales. Forecasts there are not reliable.'
                    : 'Sales at $branchName are ${stale.daysOld} days old. Import fresh sales for a reliable forecast.',
              ),
            ),
          ],
          const SizedBox(height: 14),
          MedivoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardTitle(
                  '${medicine.name} at $branchName',
                  subtitle: 'Last 28 recorded days and the next $horizon days.',
                  trailing: SegmentedButton<ChartKind>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(value: ChartKind.line, label: Text('Line')),
                      ButtonSegment(value: ChartKind.bar, label: Text('Bar')),
                      ButtonSegment(value: ChartKind.area, label: Text('Area')),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => ref.read(forecastKindProvider.notifier).state = s.first,
                  ),
                ),
                const SizedBox(height: 16),
                result.when(
                  loading: () => const SizedBox(
                    height: 250,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Column(
                    children: [
                      ErrorBanner(e is ForecastProblem ? e.message : 'Could not load sales. Check your connection.'),
                      const SizedBox(height: 10),
                      OutlinedButton(onPressed: reload, child: const Text('Try again')),
                    ],
                  ),
                  data: (r) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ForecastChart(result: r, kind: kind),
                      DataNotes(result: r),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (result.valueOrNull != null) ...[
            const SizedBox(height: 14),
            MetricsGrid(result: result.value!, medicine: medicine),
          ],
          const SizedBox(height: 14),
          JobCard(query: query, result: result.valueOrNull, canRun: canRun),
          const SizedBox(height: 14),
          RecentRunsCard(keyArgs: key),
        ],
      ),
    );
  }
}