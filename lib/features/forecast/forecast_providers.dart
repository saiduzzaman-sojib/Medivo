import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_providers.dart';
import '../overview/overview_providers.dart';
import '../security/audit_controller.dart';
import 'data/forecast_engine.dart';
import 'data/forecast_models.dart';
import 'data/forecast_repository.dart';

final forecastRepositoryProvider = Provider<ForecastRepository>(
  (ref) => ForecastRepository(ref.watch(supabaseClientProvider)),
);

/// Null means "the first one in the list".
final forecastMedicineProvider = StateProvider.autoDispose<String?>((ref) => null);
final forecastBranchProvider = StateProvider.autoDispose<String?>((ref) => null);
final forecastHorizonProvider = StateProvider.autoDispose<int>((ref) => 14);
final forecastSourceProvider =
    StateProvider.autoDispose<ForecastSource>((ref) => ForecastSource.model);
final forecastPercentProvider = StateProvider.autoDispose<double>((ref) => 0);
final forecastAssumptionProvider = StateProvider.autoDispose<String>((ref) => '');
final forecastKindProvider = StateProvider.autoDispose<ChartKind>((ref) => ChartKind.line);

/// The last 60 days of recorded sales for one medicine at one branch.
final historyProvider =
    FutureProvider.autoDispose.family<List<HistoryDay>, DemandKey>((ref, key) async {
  final rows = await ref.watch(overviewRepositoryProvider).salesRows(
        medicineId: key.medicineId,
        branchId: key.branchId,
        days: 62,
      );
  return buildHistory(rows, today: DateTime.now(), days: 60);
});

typedef ForecastQuery = ({
  String medicineId,
  String branchId,
  int horizon,
  ForecastSource source,
  double percent,
  double unitPrice,
});

/// Calculated on the device from the recorded sales. Cheap, so it updates live.
final forecastResultProvider = Provider.autoDispose
    .family<AsyncValue<ForecastResult>, ForecastQuery>((ref, q) {
  final h = ref.watch(historyProvider((medicineId: q.medicineId, branchId: q.branchId)));
  if (h.hasError) return AsyncError(h.error!, h.stackTrace ?? StackTrace.current);
  final hist = h.valueOrNull;
  if (hist == null) return const AsyncLoading();
  try {
    return AsyncData(computeForecast(
      history: hist,
      horizon: q.horizon,
      source: q.source,
      percent: q.percent,
      unitPrice: q.unitPrice,
    ));
  } catch (e, st) {
    return AsyncError(e, st);
  }
});

final recentRunsProvider =
    FutureProvider.autoDispose.family<List<RecentRun>, DemandKey>((ref, key) {
  return ref.watch(forecastRepositoryProvider).recentRuns(
        medicineId: key.medicineId,
        branchId: key.branchId,
      );
});

enum JobPhase { idle, working, succeeded, failed }

class JobState {
  const JobState({
    this.phase = JobPhase.idle,
    this.step = '',
    this.progress = 0,
    this.runId,
    this.attempt = 0,
    this.reused = false,
    this.message,
  });

  final JobPhase phase;
  final String step;
  final double progress;
  final String? runId;
  final int attempt;
  final bool reused;
  final String? message;
}

/// The job flow: accept (queued), begin (running), complete (succeeded).
/// If the app dies in the middle, pressing Run again resumes the same run.
class ForecastJobController extends AutoDisposeNotifier<JobState> {
  @override
  JobState build() => const JobState();

  Future<void> run({
    required ForecastQuery query,
    required ForecastResult result,
    required String assumption,
    bool simulateCrash = false,
  }) async {
    if (state.phase == JobPhase.working) return;
    final repo = ref.read(forecastRepositoryProvider);
    final manual = query.source == ForecastSource.manual;
    final hash = forecastInputHash(
      medicineId: query.medicineId,
      branchId: query.branchId,
      horizon: query.horizon,
      source: query.source,
      percent: query.percent,
      assumption: assumption,
      series: result.cleaned,
    );

    state = const JobState(phase: JobPhase.working, step: 'Sending to the server', progress: 0.15);
    String? runId;
    var attempt = 0;
    try {
      final start = await repo.start(
        medicineId: query.medicineId,
        branchId: query.branchId,
        horizon: query.horizon,
        source: query.source,
        inputHash: hash,
        assumption: manual ? assumption.trim() : null,
        params: manual ? {'percent': query.percent} : const {},
      );
      if (!start.ok) {
        state = JobState(phase: JobPhase.failed, message: start.userMessage);
        return;
      }
      runId = start.data['run_id'] as String;
      attempt = (start.data['attempt'] as num?)?.toInt() ?? 1;

      if (start.data['reused'] == true) {
        state = JobState(
          phase: JobPhase.succeeded,
          step: 'Done',
          progress: 1,
          runId: runId,
          attempt: attempt,
          reused: true,
          message: 'Same input as a finished run, so nothing was calculated again.',
        );
        return;
      }

      state = JobState(
        phase: JobPhase.working,
        step: 'Queued',
        progress: 0.35,
        runId: runId,
        attempt: attempt,
      );
      final begun = await repo.begin(runId);
      if (!begun.ok) {
        state = JobState(phase: JobPhase.failed, runId: runId, attempt: attempt, message: begun.userMessage);
        return;
      }
      state = JobState(
        phase: JobPhase.working,
        step: 'Running',
        progress: 0.65,
        runId: runId,
        attempt: attempt,
      );

      if (simulateCrash) {
        state = JobState(
          phase: JobPhase.failed,
          runId: runId,
          attempt: attempt,
          message:
              'Simulated crash. The run stays unfinished on the server. Press Run again to resume the same run.',
        );
        return;
      }

      final done = await repo.complete(runId, result.points, result.metrics);
      if (!done.ok) {
        await repo.fail(runId, 'complete_rejected');
        state = JobState(phase: JobPhase.failed, runId: runId, attempt: attempt, message: done.userMessage);
        return;
      }
      state = JobState(
        phase: JobPhase.succeeded,
        step: 'Done',
        progress: 1,
        runId: runId,
        attempt: attempt,
      );
    } catch (_) {
      state = JobState(
        phase: JobPhase.failed,
        runId: runId,
        attempt: attempt,
        message: 'Could not reach the server. Run again to resume.',
      );
    } finally {
      ref.invalidate(recentRunsProvider);
      ref.invalidate(auditControllerProvider);
    }
  }
}

final forecastJobProvider =
    AutoDisposeNotifierProvider<ForecastJobController, JobState>(ForecastJobController.new);