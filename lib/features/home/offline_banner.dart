import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/offline_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/medivo_card.dart';
import '../forecast/forecast_providers.dart';
import '../overview/overview_providers.dart';
import '../plan/plan_providers.dart';
import '../security/audit_controller.dart';
import '../stock/stock_controller.dart';

/// Asks every screen to load again.
void refreshEverything(WidgetRef ref) {
  ref.invalidate(stockControllerProvider);
  ref.invalidate(freshnessProvider);
  ref.invalidate(demandSeriesProvider);
  ref.invalidate(historyProvider);
  ref.invalidate(recentRunsProvider);
  ref.invalidate(plansProvider);
  ref.invalidate(transfersProvider);
  ref.invalidate(outcomesProvider);
  ref.invalidate(auditControllerProvider);
}

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(offlineStatusProvider).state;
    if (!s.offline) return const SizedBox.shrink();
    final c = context.mc;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: MedivoCard(
        color: c.warning.withValues(alpha: 0.12),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: c.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('You are offline', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    s.savedAt == null
                        ? 'Some screens have no saved data yet. Changes need a connection.'
                        : 'Showing data saved ${formatDateTime(s.savedAt!)}. Changes need a connection.',
                    style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => refreshEverything(ref),
              child: Text('Try again',
                  style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}