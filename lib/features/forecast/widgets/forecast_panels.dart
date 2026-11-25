import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/medivo_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../overview/overview_providers.dart';
import '../../overview/widgets/overview_cards.dart';
import '../../stock/data/stock_models.dart';
import '../data/forecast_models.dart';
import '../forecast_providers.dart';

class MetricsGrid extends StatelessWidget {
  const MetricsGrid({super.key, required this.result, required this.medicine});

  final ForecastResult result;
  final Medicine medicine;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final m = result.metrics;
    final imp = m.improvementPct;

    return LayoutBuilder(
      builder: (context, cons) {
        final perRow = cons.maxWidth >= 700 ? 4 : 2;
        final w = (cons.maxWidth - 12 * (perRow - 1)) / perRow;

        Widget tile(String label, String value, {String? note, Color? noteColor}) => SizedBox(
              width: w,
              child: MedivoCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: c.muted, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      Text(note,
                          style: TextStyle(
                              color: noteColor ?? c.muted,
                              fontSize: 12,
                              fontWeight: noteColor == null ? FontWeight.w400 : FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                tile(
                  'Model error (MAE)',
                  '${m.mae.toStringAsFixed(1)} /day',
                  note: imp == null
                      ? null
                      : (imp >= 0
                          ? '${imp.toStringAsFixed(0)}% better than baseline'
                          : '${(-imp).toStringAsFixed(0)}% worse than baseline'),
                  noteColor: imp == null ? null : (imp >= 0 ? c.primary : c.warning),
                ),
                tile('Baseline error (MAE)', '${m.maeBaseline.toStringAsFixed(1)} /day',
                    note: 'Same weekday last week'),
                tile('Weighted error', '${(m.wape * 100).toStringAsFixed(1)}%',
                    note: 'Errors divided by total sales'),
                tile('Bias', '${m.bias >= 0 ? '+' : ''}${m.bias.toStringAsFixed(1)} /day',
                    note: m.bias < 0 ? 'Model tends to under-forecast' : 'Model tends to over-forecast'),
                tile('Interval coverage', '${(m.coverage * 100).toStringAsFixed(0)}%',
                    note: 'Target 80%'),
                tile('Planning cost: model', formatTaka(m.cost), note: 'Back-test, last 14 days'),
                tile('Planning cost: baseline', formatTaka(m.costBaseline), note: 'Back-test, last 14 days'),
                tile('Lead time · pack', '${medicine.leadTimeDays} days · ${medicine.packSize}',
                    note: 'Used when planning orders'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              result.source == ForecastSource.model
                  ? 'Numbers come from replaying the last 14 days using only the data before each day. Thresholds are agreed with the owner before any accuracy is claimed.'
                  : 'These numbers describe the AI model and the baseline. A ${result.source.label.toLowerCase()} forecast is not back-tested.',
              style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
            ),
          ],
        );
      },
    );
  }
}

class DataNotes extends StatelessWidget {
  const DataNotes({super.key, required this.result});

  final ForecastResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final lines = <String>[
      if (result.stockoutDays > 0)
        '${result.stockoutDays} stockout day${result.stockoutDays == 1 ? '' : 's'} are treated as missing demand, not zero demand.',
      if (result.promotionDays > 0)
        '${result.promotionDays} promotion day${result.promotionDays == 1 ? '' : 's'} are replaced by normal demand, so a sale does not inflate the forecast.',
      if (result.returnDays > 0)
        '${result.returnDays} return day${result.returnDays == 1 ? '' : 's'} are added back to routine demand.',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ManualForm extends ConsumerStatefulWidget {
  const ManualForm({super.key});

  @override
  ConsumerState<ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends ConsumerState<ManualForm> {
  late final TextEditingController _pct;
  late final TextEditingController _why;

  @override
  void initState() {
    super.initState();
    final p = ref.read(forecastPercentProvider);
    _pct = TextEditingController(text: p == 0 ? '' : p.toString());
    _why = TextEditingController(text: ref.read(forecastAssumptionProvider));
  }

  @override
  void dispose() {
    _pct.dispose();
    _why.dispose();
    super.dispose();
  }

  InputDecoration _dec(MedivoColors c, String label, {String? hint}) {
    OutlineInputBorder b(Color color, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: w),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: c.surface,
      labelStyle: TextStyle(color: c.muted),
      border: b(c.line),
      enabledBorder: b(c.line),
      focusedBorder: b(c.primary, 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return MedivoCard(
      color: c.raised,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Manual adjustment', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Changes the baseline by a percentage. An assumption is required to save the run.',
            style: TextStyle(color: c.muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pct,
            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: _dec(c, 'Change in percent (-50 to 100)', hint: 'for example 10'),
            onChanged: (v) {
              final n = double.tryParse(v.trim().replaceAll('+', ''));
              ref.read(forecastPercentProvider.notifier).state =
                  n == null ? 0 : n.clamp(-50, 100).toDouble();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _why,
            maxLength: 160,
            decoration: _dec(c, 'Assumption', hint: 'for example school holiday week'),
            onChanged: (v) => ref.read(forecastAssumptionProvider.notifier).state = v,
          ),
        ],
      ),
    );
  }
}

class JobCard extends ConsumerWidget {
  const JobCard({
    super.key,
    required this.query,
    required this.result,
    required this.canRun,
  });

  final ForecastQuery query;
  final ForecastResult? result;
  final bool canRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final job = ref.watch(forecastJobProvider);
    final busy = job.phase == JobPhase.working;
    final ready = canRun && result != null && !busy;

    void run({bool crash = false}) => ref.read(forecastJobProvider.notifier).run(
          query: query,
          result: result!,
          assumption: ref.read(forecastAssumptionProvider),
          simulateCrash: crash,
        );

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Save this forecast',
            subtitle:
                'Records the run on the server with a fingerprint of its inputs, its model version and its results. Running the same input again reuses the same run.',
          ),
          const SizedBox(height: 14),
          if (!canRun)
            Row(
              children: [
                Icon(Icons.lock_rounded, color: c.muted, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Your role cannot run this kind of forecast.')),
              ],
            )
          else
            FilledButton.icon(
              onPressed: ready ? () => run() : null,
              icon: busy
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: c.muted),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(busy ? job.step : 'Run forecast'),
            ),
          if (job.phase != JobPhase.idle) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(
                value: job.phase == JobPhase.failed ? 0.65 : job.progress,
                minHeight: 8,
                color: job.phase == JobPhase.failed ? c.danger : c.primary,
                backgroundColor: c.raised,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(
                  label: switch (job.phase) {
                    JobPhase.succeeded => job.reused ? 'Reused' : 'Succeeded',
                    JobPhase.failed => 'Failed',
                    _ => job.step,
                  },
                  color: switch (job.phase) {
                    JobPhase.succeeded => c.primary,
                    JobPhase.failed => c.danger,
                    _ => c.secondary,
                  },
                ),
                if (job.runId != null)
                  Text('Run ${job.runId!.substring(0, 8)} · attempt ${job.attempt}',
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
              ],
            ),
            if (job.message != null) ...[
              const SizedBox(height: 8),
              Text(job.message!,
                  style: TextStyle(
                      color: job.phase == JobPhase.failed ? c.danger : c.muted, height: 1.35)),
            ],
          ],
          if (kDebugMode && canRun) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: ready ? () => run(crash: true) : null,
              child: Text('Simulate a crash (debug builds only)',
                  style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Today the forecast is calculated on this device and recorded on the server. A server-side worker replaces this in a later step.',
            style: TextStyle(color: c.muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class RecentRunsCard extends ConsumerWidget {
  const RecentRunsCard({super.key, required this.keyArgs});

  final DemandKey keyArgs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final async = ref.watch(recentRunsProvider(keyArgs));

    Color statusColor(String s) => switch (s) {
          'succeeded' => c.primary,
          'failed' => c.danger,
          'running' => c.secondary,
          _ => c.warning,
        };

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle('Recent runs', subtitle: 'Saved runs for this medicine and branch.'),
          const SizedBox(height: 8),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Text('Could not load recent runs.', style: TextStyle(color: c.danger)),
            data: (runs) {
              if (runs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No saved runs yet.', style: TextStyle(color: c.muted)),
                );
              }
              return Column(
                children: [
                  for (final r in runs)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r.horizon}-day ${r.source} forecast',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  '${formatDateTime(r.createdAt)} · ${r.modelVersion} · attempt ${r.attempts}'
                                  '${r.mae != null ? ' · MAE ${r.mae!.toStringAsFixed(1)}' : ''}',
                                  style: TextStyle(color: c.muted, fontSize: 12.5),
                                ),
                                if (r.assumption != null)
                                  Text('Assumption: ${r.assumption}',
                                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(label: r.status, color: statusColor(r.status)),
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