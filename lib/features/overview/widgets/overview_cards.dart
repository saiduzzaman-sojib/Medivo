import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/expiry.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/medivo_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../stock/data/stock_models.dart';
import '../../stock/widgets/stock_style.dart';
import '../data/overview_calc.dart';
import '../overview_providers.dart';
import 'charts.dart';

class CardTitle extends StatelessWidget {
  const CardTitle(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: TextStyle(color: c.muted, height: 1.35)),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.kpis});

  final OverviewKpis kpis;

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
          const Text('Stock expiring in the next 90 days',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(formatTaka(kpis.atRiskValue),
              style: const TextStyle(
                  color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 4),
          Text(
            '${kpis.atRiskCount} batch${kpis.atRiskCount == 1 ? '' : 'es'} need a plan before they expire.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              pill('Already expired', formatTaka(kpis.expiredValue)),
              pill('Healthy stock value', formatTaka(kpis.stockValue)),
            ],
          ),
        ],
      ),
    );
  }
}

class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.kpis});

  final OverviewKpis kpis;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return LayoutBuilder(
      builder: (context, cons) {
        final perRow = cons.maxWidth >= 700 ? 4 : 2;
        final w = (cons.maxWidth - 12 * (perRow - 1)) / perRow;
        Widget tile(String label, String value, String note, Color color) => SizedBox(
              width: w,
              child: MedivoCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: c.muted, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text(value,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                    const SizedBox(height: 2),
                    Text(note, style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ),
              ),
            );
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            tile('Healthy stock', formatTaka(kpis.stockValue), 'not expired or recalled', c.ink),
            tile('Within 30 days', formatTaka(kpis.soonValue),
                '${kpis.soonCount} batches', c.warning),
            tile('Expired', formatTaka(kpis.expiredValue), '${kpis.expiredCount} batches',
                c.danger),
            tile('Need validation', '${kpis.needValidation}', 'batches to count', c.secondary),
          ],
        );
      },
    );
  }
}

class StaleWarnings extends StatelessWidget {
  const StaleWarnings({super.key, required this.entries});

  final List<FreshnessEntry> entries;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final stale = [for (final e in entries) if (e.stale) e];
    if (stale.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final e in stale)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MedivoCard(
              padding: const EdgeInsets.all(14),
              color: c.warning.withValues(alpha: 0.10),
              child: Row(
                children: [
                  StatusChip(label: 'Stale input', color: c.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      e.daysOld == null
                          ? '${e.branch} has no sales recorded yet.'
                          : '${e.branch} sales are ${e.daysOld} days old, so forecasts there are less reliable.',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class DemandCard extends ConsumerWidget {
  const DemandCard({super.key, required this.data});

  final StockData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final medId = ref.watch(demandMedicineProvider) ?? data.medicines.firstOrNull?.id;
    final brId = ref.watch(demandBranchProvider) ?? data.branches.firstOrNull?.id;
    final kind = ref.watch(demandKindProvider);

    if (medId == null || brId == null) {
      return const MedivoCard(child: Text('No medicines or branches to show yet.'));
    }
    final series = ref.watch(demandSeriesProvider((medicineId: medId, branchId: brId)));

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle(
            'Recorded demand',
            subtitle: 'Units sold per day, last 28 days. Forecasts are added in a later step.',
            trailing: SegmentedButton<ChartKind>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: ChartKind.line, label: Text('Line')),
                ButtonSegment(value: ChartKind.bar, label: Text('Bar')),
                ButtonSegment(value: ChartKind.area, label: Text('Area')),
              ],
              selected: {kind},
              onSelectionChanged: (s) =>
                  ref.read(demandKindProvider.notifier).state = s.first,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              DropdownMenu<String>(
                width: 220,
                requestFocusOnTap: false,
                label: const Text('Medicine'),
                initialSelection: medId,
                dropdownMenuEntries: [
                  for (final m in data.medicines) DropdownMenuEntry(value: m.id, label: m.name),
                ],
                onSelected: (v) {
                  if (v != null) ref.read(demandMedicineProvider.notifier).state = v;
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
                  if (v != null) ref.read(demandBranchProvider.notifier).state = v;
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          series.when(
            loading: () => const SizedBox(
              height: 230,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Column(
              children: [
                const ErrorBanner('Could not load sales. Check your connection.'),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => ref.invalidate(demandSeriesProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
            data: (days) {
              final stockouts = days.where((d) => d.stockout).length;
              final promos = days.where((d) => d.promotion).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DemandChart(days: days, kind: kind),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      LegendDot(
                        color: kind == ChartKind.bar ? c.secondary : c.primary,
                        label: 'Units sold',
                      ),
                      if (kind == ChartKind.bar && promos > 0)
                        LegendDot(color: c.warning, label: 'Promotion day'),
                    ],
                  ),
                  if (stockouts > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '$stockouts stockout day${stockouts == 1 ? '' : 's'} are treated as missing demand, not zero demand.',
                        style: TextStyle(color: c.muted, fontSize: 12.5),
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

class HealthCard extends ConsumerWidget {
  const HealthCard({super.key, required this.data});

  final StockData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(healthKindProvider);
    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle(
            'Stock health by value',
            subtitle: 'How much value sits in each expiry window.',
            trailing: SegmentedButton<HealthKind>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: HealthKind.donut, label: Text('Donut')),
                ButtonSegment(value: HealthKind.pie, label: Text('Pie')),
                ButtonSegment(value: HealthKind.bars, label: Text('Bars')),
              ],
              selected: {kind},
              onSelectionChanged: (s) =>
                  ref.read(healthKindProvider.notifier).state = s.first,
            ),
          ),
          const SizedBox(height: 16),
          HealthChart(buckets: bucketValues(data.items), kind: kind),
        ],
      ),
    );
  }
}

class ExposureCard extends StatelessWidget {
  const ExposureCard({super.key, required this.data});

  final StockData data;

  @override
  Widget build(BuildContext context) {
    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Expiry exposure by branch',
            subtitle: 'Bar length is the branch stock value, split by expiry window.',
          ),
          const SizedBox(height: 16),
          BranchExposure(data: bucketsByBranch(data.items)),
        ],
      ),
    );
  }
}

class RiskCard extends StatelessWidget {
  const RiskCard({super.key, required this.data});

  final StockData data;

  @override
  Widget build(BuildContext context) {
    final risks = riskByMedicine(data.items).take(6).toList();
    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Expiry value by medicine',
            subtitle: 'Biggest risks first. Tap a bar to see the value.',
          ),
          const SizedBox(height: 16),
          MedicineRiskChart(risks: risks),
        ],
      ),
    );
  }
}

class AttentionCard extends StatelessWidget {
  const AttentionCard({super.key, required this.data, required this.freshness});

  final StockData data;
  final List<FreshnessEntry> freshness;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final kpis = computeKpis(data.items);
    final top = topExpiring(data.items);
    final stale = [for (final f in freshness) if (f.stale) f];

    Widget row(IconData icon, Color color, String title, String sub, String chip) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/stock'),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: chip, color: color),
            ],
          ),
        ),
      );
    }

    final rows = <Widget>[
      for (final i in top)
        row(
          Icons.hourglass_bottom_rounded,
          levelColor(c, expiryLevel(i.daysLeft())),
          '${i.medicine.name} · ${i.batchCode}',
          '${i.branch.name} · ${i.quantity} units · ${formatTaka(i.value)}',
          expiryLabel(i.daysLeft()),
        ),
      if (kpis.needValidation > 0)
        row(
          Icons.rule_rounded,
          c.secondary,
          '${kpis.needValidation} batches need validation',
          'A pharmacist confirms the counts in the Stock tab.',
          'Validate',
        ),
      for (final f in stale)
        row(
          Icons.update_rounded,
          c.warning,
          'Sales data is old for ${f.branch}',
          f.daysOld == null ? 'No sales recorded yet.' : '${f.daysOld} days since the last sale was recorded.',
          'Import',
        ),
    ];

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle('Needs attention', subtitle: 'Tap an item to open the Stock tab.'),
          const SizedBox(height: 6),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Nothing needs attention right now.',
                    style: TextStyle(color: c.muted)),
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }
}