import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/expiry.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/medivo_card.dart';
import '../../shared/widgets/status_chip.dart';
import 'data/stock_models.dart';
import 'stock_controller.dart';
import 'widgets/add_batch_sheet.dart';
import 'widgets/batch_sheet.dart';
import 'widgets/import_card.dart';
import 'widgets/stock_style.dart';

class StockPage extends ConsumerWidget {
  const StockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final async = ref.watch(stockControllerProvider);
    final data = async.valueOrNull;
    final canAdd = user.can(Permission.addBatch);

    Future<void> reload() async {
      ref.invalidate(freshnessProvider);
      try {
        // ignore: unused_result
        await ref.refresh(stockControllerProvider.future);
      } catch (_) {}
    }

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stock and batches',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Validate counts, add batches and bring in sales.',
                        style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
              if (canAdd || kDebugMode)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: data == null ? null : () => showAddBatchSheet(context, data),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(canAdd ? 'Add batch' : 'Add (debug)'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (data == null) ...[
            if (async.isLoading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              MedivoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ErrorBanner('Could not load stock. Check your connection.'),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: reload, child: const Text('Try again')),
                  ],
                ),
              ),
          ] else ...[
            _Summary(data: data),
            const SizedBox(height: 14),
            ImportCard(canImport: user.can(Permission.importData)),
            const SizedBox(height: 14),
            const _FreshnessCard(),
            const SizedBox(height: 14),
            _BatchList(data: data),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.data});

  final StockData data;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return LayoutBuilder(
      builder: (context, cons) {
        final perRow = cons.maxWidth >= 700 ? 4 : 2;
        final w = (cons.maxWidth - 12 * (perRow - 1)) / perRow;
        Widget kpi(String label, int value, Color color) => SizedBox(
              width: w,
              child: MedivoCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: c.muted, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text('$value',
                        style: TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800, color: color)),
                  ],
                ),
              ),
            );
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            kpi('Batches', data.total, c.ink),
            kpi('Expiring in 30 days', data.expiringSoon(), c.warning),
            kpi('Expired', data.expired(), c.danger),
            kpi('Need validation', data.needValidation(), c.secondary),
          ],
        );
      },
    );
  }
}

class _FreshnessCard extends ConsumerWidget {
  const _FreshnessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final async = ref.watch(freshnessProvider);
    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Data freshness',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text('Old sales data lowers forecast quality, so it is shown here.',
              style: TextStyle(color: c.muted)),
          const SizedBox(height: 8),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Text('Could not load data freshness.',
                style: TextStyle(color: c.danger)),
            data: (list) => Column(
              children: [
                for (final f in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(f.branch,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        StatusChip(
                          label: f.daysOld == null
                              ? 'No sales yet'
                              : '${f.stale ? 'Stale' : 'Fresh'} · ${f.daysOld} day${f.daysOld == 1 ? '' : 's'} old',
                          color: f.stale ? c.warning : c.primary,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BatchList extends ConsumerWidget {
  const _BatchList({required this.data});

  final StockData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final query = ref.watch(stockQueryProvider);
    final filter = ref.watch(stockFilterProvider);
    final items = filterItems(data.items, query: query, filter: filter);

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => ref.read(stockQueryProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Search batch, medicine or branch',
              prefixIcon: Icon(Icons.search_rounded, color: c.muted),
              filled: true,
              fillColor: c.raised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.primary, width: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in StockFilter.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: filter == f,
                  onSelected: (_) => ref.read(stockFilterProvider.notifier).state = f,
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text('No batches match. Clear the search or change the filter.',
                    textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
              ),
            ),
          for (final it in items) _BatchTile(item: it),
        ],
      ),
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final days = item.daysLeft();
    final level = expiryLevel(days);
    final color = item.recalled ? c.danger : levelColor(c, level);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showBatchSheet(context, item),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.inventory_2_rounded, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.medicine.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${item.batchCode} · ${item.branch.name} · ${item.quantity} units · ${formatTaka(item.value)}',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(
                  label: item.recalled ? 'Recalled' : expiryLabel(days),
                  color: color,
                ),
                const SizedBox(height: 6),
                Icon(
                  item.validated ? Icons.verified_rounded : Icons.pending_outlined,
                  size: 18,
                  color: item.validated ? c.primary : c.muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}