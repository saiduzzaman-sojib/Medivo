import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_providers.dart';
import 'data/overview_calc.dart';
import 'data/overview_repository.dart';

enum ChartKind { line, bar, area }

enum HealthKind { donut, pie, bars }

final overviewRepositoryProvider = Provider<OverviewRepository>(
  (ref) => OverviewRepository(ref.watch(supabaseClientProvider)),
);

/// Null means "the first one in the list".
final demandMedicineProvider = StateProvider.autoDispose<String?>((ref) => null);
final demandBranchProvider = StateProvider.autoDispose<String?>((ref) => null);
final demandKindProvider = StateProvider.autoDispose<ChartKind>((ref) => ChartKind.line);
final healthKindProvider = StateProvider.autoDispose<HealthKind>((ref) => HealthKind.donut);

typedef DemandKey = ({String medicineId, String branchId});

final demandSeriesProvider =
    FutureProvider.autoDispose.family<List<DemandDay>, DemandKey>((ref, key) async {
  final rows = await ref.watch(overviewRepositoryProvider).salesRows(
        medicineId: key.medicineId,
        branchId: key.branchId,
        days: 30,
      );
  return buildDemandSeries(rows, today: DateTime.now(), days: 28);
});