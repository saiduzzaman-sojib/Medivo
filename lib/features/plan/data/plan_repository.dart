import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/rpc_result.dart';
import '../../../core/utils/format.dart';
import 'plan_models.dart';

/// Reading uses normal queries (the database only returns the person's own
/// tenant). Every change goes through a database function.
class PlanRepository {
  PlanRepository(this._client);

  final SupabaseClient _client;

  /// All recent sales. The server returns at most 1000 rows per request, so
  /// this reads page by page.
  Future<List<Map<String, dynamic>>> allSalesRows({int days = 62}) async {
    final from = isoDate(DateTime.now().subtract(Duration(days: days)));
    final out = <Map<String, dynamic>>[];
    const page = 1000;
    for (var p = 0; p < 20; p++) {
      final rows = await _client
          .from('medicine_sales')
          .select('id, medicine_id, branch_id, day, quantity, flag')
          .gte('day', from)
          .order('id')
          .range(p * page, p * page + page - 1);
      for (final r in rows) {
        out.add(Map<String, dynamic>.from(r));
      }
      if (rows.length < page) break;
    }
    return out;
  }

  Future<RpcResult> createPlan({
    required int horizon,
    required String source,
    required String inputHash,
    required List<Map<String, dynamic>> moves,
    required List<Map<String, dynamic>> orders,
    required double riskBefore,
    required double riskAfter,
    required List<Map<String, dynamic>> transfers,
  }) async {
    final raw = await _client.rpc('create_plan', params: {
      'p_horizon': horizon,
      'p_source': source,
      'p_input_hash': inputHash,
      'p_moves': moves,
      'p_orders': orders,
      'p_risk_before': (riskBefore * 100).round() / 100,
      'p_risk_after': (riskAfter * 100).round() / 100,
      'p_transfers': transfers,
    });
    return RpcResult.fromRaw(raw);
  }

  Future<List<PlanRecord>> plans() async {
    final rows = await _client
        .from('stock_plans')
        .select()
        .order('created_at', ascending: false)
        .limit(12);
    return [for (final r in rows) PlanRecord.fromJson(Map<String, dynamic>.from(r))];
  }

  Future<List<TransferRecord>> transfers(String planId) async {
    final rows = await _client
        .from('transfers')
        .select()
        .eq('plan_id', planId)
        .order('created_at', ascending: true);
    return [for (final r in rows) TransferRecord.fromJson(Map<String, dynamic>.from(r))];
  }

  Future<List<OutcomeRecord>> outcomes() async {
    final rows = await _client
        .from('outcomes')
        .select()
        .order('created_at', ascending: true)
        .limit(24);
    return [for (final r in rows) OutcomeRecord.fromJson(Map<String, dynamic>.from(r))];
  }

  Future<RpcResult> review(String planId, int expectedVersion) async => RpcResult.fromRaw(
        await _client.rpc('review_plan', params: {
          'p_plan': planId,
          'p_expected_version': expectedVersion,
        }),
      );

  Future<RpcResult> approve(String planId, int expectedVersion, bool handlingConfirmed) async =>
      RpcResult.fromRaw(
        await _client.rpc('approve_plan', params: {
          'p_plan': planId,
          'p_expected_version': expectedVersion,
          'p_handling_confirmed': handlingConfirmed,
        }),
      );

  Future<RpcResult> returnPlan(String planId, String reason) async => RpcResult.fromRaw(
        await _client.rpc('return_plan', params: {'p_plan': planId, 'p_reason': reason}),
      );

  Future<RpcResult> decideTransfer(String transferId, bool approve) async => RpcResult.fromRaw(
        await _client.rpc('decide_transfer', params: {
          'p_transfer': transferId,
          'p_approve': approve,
        }),
      );

  Future<RpcResult> recallBatch(String batchId, String reason) async => RpcResult.fromRaw(
        await _client.rpc('recall_batch', params: {'p_batch': batchId, 'p_reason': reason}),
      );

  Future<RpcResult> recordOutcome({
    required String planId,
    required String label,
    required double baseline,
    required double planCost,
  }) async =>
      RpcResult.fromRaw(
        await _client.rpc('record_outcome', params: {
          'p_plan': planId,
          'p_label': label,
          'p_baseline': (baseline * 100).round() / 100,
          'p_plan_cost': (planCost * 100).round() / 100,
        }),
      );
}