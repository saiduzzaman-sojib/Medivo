import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medivo/core/network/rpc_result.dart';
import 'package:medivo/core/network/supabase_providers.dart';
import 'package:medivo/features/forecast/data/forecast_engine.dart';
import 'package:medivo/features/forecast/data/forecast_models.dart';
import 'package:medivo/features/plan/data/plan_engine.dart';
import 'package:medivo/features/plan/data/plan_models.dart';
import 'package:medivo/features/plan/data/plan_repository.dart';
import 'package:medivo/features/security/audit_controller.dart';
import 'package:medivo/features/stock/stock_controller.dart';



final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => PlanRepository(ref.watch(supabaseClientProvider)),
);

enum PlanTab {
  orders('Orders'),
  transfers('Transfers'),
  recalls('Recalls'),
  outcomes('Outcomes');

  const PlanTab(this.label);
  final String label;
}

final planTabProvider = StateProvider.autoDispose<PlanTab>((ref) => PlanTab.orders);
final planHorizonProvider = StateProvider.autoDispose<int>((ref) => 14);
final planSourceProvider =
    StateProvider.autoDispose<ForecastSource>((ref) => ForecastSource.model);

/// Null means "the newest plan".
final selectedPlanIdProvider = StateProvider.autoDispose<String?>((ref) => null);

final plansProvider = FutureProvider.autoDispose<List<PlanRecord>>(
  (ref) => ref.watch(planRepositoryProvider).plans(),
);

final selectedPlanProvider = Provider.autoDispose<AsyncValue<PlanRecord?>>((ref) {
  final plans = ref.watch(plansProvider);
  final id = ref.watch(selectedPlanIdProvider);
  return plans.whenData((list) {
    if (list.isEmpty) return null;
    return list.firstWhere((p) => p.id == id, orElse: () => list.first);
  });
});

final transfersProvider = FutureProvider.autoDispose.family<List<TransferRecord>, String>(
  (ref, planId) => ref.watch(planRepositoryProvider).transfers(planId),
);

final outcomesProvider = FutureProvider.autoDispose<List<OutcomeRecord>>(
  (ref) => ref.watch(planRepositoryProvider).outcomes(),
);

/// Runs a database call and turns a network failure into a normal answer.
Future<RpcResult> safeRpc(Future<RpcResult> Function() call) async {
  try {
    return await call();
  } catch (_) {
    return const RpcResult(
      ok: false,
      status: 500,
      message: 'Could not reach the server. Check your connection and try again.',
    );
  }
}

/// Call after any change, so every list and the audit log show the new state.
void refreshPlanData(WidgetRef ref) {
  ref.invalidate(plansProvider);
  ref.invalidate(transfersProvider);
  ref.invalidate(outcomesProvider);
  ref.invalidate(stockControllerProvider);
  ref.invalidate(freshnessProvider);
  ref.invalidate(auditControllerProvider);
}

class GenerateState {
  const GenerateState({
    this.working = false,
    this.step = '',
    this.message,
    this.error,
    this.skipped = const [],
  });

  final bool working;
  final String step;
  final String? message;
  final String? error;
  final List<String> skipped;
}

/// Reads all sales, forecasts every medicine and branch, plans orders and
/// transfers, and saves the plan on the server.
class GenerateController extends AutoDisposeNotifier<GenerateState> {
  @override
  GenerateState build() => const GenerateState();

  Future<void> run() async {
    if (state.working) return;
    final data = ref.read(stockControllerProvider).valueOrNull;
    if (data == null) {
      state = const GenerateState(error: 'Stock is still loading. Try again in a moment.');
      return;
    }
    final horizon = ref.read(planHorizonProvider);
    final source = ref.read(planSourceProvider);
    final repo = ref.read(planRepositoryProvider);

    try {
      state = const GenerateState(working: true, step: 'Reading sales');
      final rows = await repo.allSalesRows();
      final byPair = <String, List<Map<String, dynamic>>>{};
      for (final r in rows) {
        byPair.putIfAbsent('${r['medicine_id']}|${r['branch_id']}', () => []).add(r);
      }

      state = const GenerateState(working: true, step: 'Forecasting');
      final forecasts = <String, List<double>>{};
      for (final m in data.medicines) {
        for (final b in data.branches) {
          final key = '${m.id}|${b.id}';
          try {
            final history = buildHistory(byPair[key] ?? const [], today: DateTime.now(), days: 60);
            final result = computeForecast(
              history: history,
              horizon: horizon,
              source: source,
              percent: 0,
              unitPrice: m.unitPrice,
            );
            forecasts[key] = [for (final p in result.points) p.value];
          } on ForecastProblem {
            continue;
          }
        }
      }

      state = const GenerateState(working: true, step: 'Planning');
      final draft = buildPlan(
        medicines: data.medicines,
        branches: data.branches,
        items: data.items,
        forecasts: forecasts,
      );
      final hash = planInputHash(
        horizon: horizon,
        source: source,
        forecasts: forecasts,
        items: data.items,
      );

      state = const GenerateState(working: true, step: 'Saving');
      final res = await repo.createPlan(
        horizon: horizon,
        source: source.key,
        inputHash: hash,
        moves: draft.movesJson,
        orders: draft.ordersJson,
        riskBefore: draft.riskBefore,
        riskAfter: draft.riskAfter,
        transfers: draft.transfersJson,
      );
      if (!res.ok) {
        state = GenerateState(error: res.userMessage, skipped: draft.skipped);
        return;
      }
      ref.read(selectedPlanIdProvider.notifier).state = res.data['plan_id'] as String?;
      ref.invalidate(plansProvider);
      ref.invalidate(transfersProvider);
      ref.invalidate(auditControllerProvider);
      state = GenerateState(
        message: res.data['reused'] == true
            ? 'These inputs match an existing plan, so it was reused.'
            : 'Plan saved as a draft: ${draft.moves.length} transfers, ${draft.orders.length} orders.',
        skipped: draft.skipped,
      );
    } catch (_) {
      state = const GenerateState(
        error: 'Could not generate the plan. Check your connection and try again.',
      );
    }
  }
}

final generateProvider =
    AutoDisposeNotifierProvider<GenerateController, GenerateState>(GenerateController.new);