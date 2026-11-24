import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_providers.dart';
import '../security/audit_controller.dart';
import 'data/stock_models.dart';
import 'data/stock_repository.dart';

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => StockRepository(ref.watch(supabaseClientProvider)),
);

/// autoDispose: nothing stays in memory after sign-out.
class StockController extends AutoDisposeAsyncNotifier<StockData> {
  @override
  Future<StockData> build() => ref.watch(stockRepositoryProvider).load();
}

final stockControllerProvider =
    AutoDisposeAsyncNotifierProvider<StockController, StockData>(StockController.new);

final freshnessProvider = FutureProvider.autoDispose<List<FreshnessEntry>>(
  (ref) => ref.watch(stockRepositoryProvider).freshness(),
);

final stockQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final stockFilterProvider = StateProvider.autoDispose<StockFilter>((ref) => StockFilter.all);

/// Call after any change, so the lists and the audit log show the new state.
void refreshAfterChange(WidgetRef ref) {
  ref.invalidate(stockControllerProvider);
  ref.invalidate(freshnessProvider);
  ref.invalidate(auditControllerProvider);
}