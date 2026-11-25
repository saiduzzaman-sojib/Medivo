import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/rpc_result.dart';
import 'forecast_models.dart';

/// Every change goes through a database function that checks the role again.
class ForecastRepository {
  ForecastRepository(this._client);

  final SupabaseClient _client;

  Future<RpcResult> start({
    required String medicineId,
    required String branchId,
    required int horizon,
    required ForecastSource source,
    required String inputHash,
    String? assumption,
    Map<String, dynamic> params = const {},
  }) async {
    final raw = await _client.rpc('start_forecast_run', params: {
      'p_medicine': medicineId,
      'p_branch': branchId,
      'p_horizon': horizon,
      'p_source': source.key,
      'p_input_hash': inputHash,
      'p_assumption': assumption,
      'p_params': params,
    });
    return RpcResult.fromRaw(raw);
  }

  Future<RpcResult> begin(String runId) async =>
      RpcResult.fromRaw(await _client.rpc('begin_forecast_run', params: {'p_run': runId}));

  Future<RpcResult> complete(
    String runId,
    List<ForecastPoint> points,
    ForecastMetrics metrics,
  ) async {
    final raw = await _client.rpc('complete_forecast_run', params: {
      'p_run': runId,
      'p_points': [for (final p in points) p.toJson()],
      'p_metrics': metrics.toJson(),
    });
    return RpcResult.fromRaw(raw);
  }

  Future<RpcResult> fail(String runId, String code) async => RpcResult.fromRaw(
        await _client.rpc('fail_forecast_run', params: {'p_run': runId, 'p_code': code}),
      );

  Future<List<RecentRun>> recentRuns({
    required String medicineId,
    required String branchId,
  }) async {
    final rows = await _client
        .from('forecast_runs')
        .select('id, source, horizon_days, status, model_version, attempts, assumption, metrics, created_at')
        .eq('medicine_id', medicineId)
        .eq('branch_id', branchId)
        .order('created_at', ascending: false)
        .limit(8);
    return [
      for (final r in rows) RecentRun.fromJson(Map<String, dynamic>.from(r)),
    ];
  }
}