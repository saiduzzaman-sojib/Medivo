import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/rpc_result.dart';
import '../../../core/utils/format.dart';
import 'stock_models.dart';

/// Reading is done with normal queries (the database only returns the person's
/// own tenant). Every change goes through a database function.
class StockRepository {
  StockRepository(this._client);

  final SupabaseClient _client;

  Future<StockData> load() async {
    final medRows = await _client.from('medicines').select().order('name');
    final brRows = await _client.from('branches').select().order('name');
    final batchRows = await _client
        .from('batches')
        .select()
        .order('expires_on', ascending: true)
        .limit(1000);

    final medicines = [
      for (final r in medRows) Medicine.fromJson(Map<String, dynamic>.from(r)),
    ];
    final branches = [
      for (final r in brRows) Branch.fromJson(Map<String, dynamic>.from(r)),
    ];
    final medMap = {for (final m in medicines) m.id: m};
    final brMap = {for (final b in branches) b.id: b};

    final items = <StockItem>[];
    for (final r in batchRows) {
      final item = StockItem.tryParse(Map<String, dynamic>.from(r), medMap, brMap);
      if (item != null) items.add(item);
    }
    return StockData(items: items, medicines: medicines, branches: branches);
  }

  Future<List<FreshnessEntry>> freshness() async {
    final raw = await _client.rpc('sales_freshness');
    return [
      for (final e in (raw as List? ?? const []))
        FreshnessEntry.fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }

  Future<RpcResult> addBatch({
    required String medicineId,
    required String branchId,
    required String code,
    required int quantity,
    required DateTime expires,
  }) async {
    final raw = await _client.rpc('add_batch', params: {
      'p_medicine': medicineId,
      'p_branch': branchId,
      'p_code': code,
      'p_quantity': quantity,
      'p_expires': isoDate(expires),
    });
    return RpcResult.fromRaw(raw);
  }

  Future<RpcResult> validateBatch(String batchId) async {
    final raw = await _client.rpc('validate_batch', params: {'p_batch': batchId});
    return RpcResult.fromRaw(raw);
  }

  Future<RpcResult> importSales({
    required List<Map<String, String>> rows,
    required String fileHash,
  }) async {
    final raw = await _client.rpc('import_sales', params: {
      'p_rows': rows,
      'p_file_hash': fileHash,
    });
    return RpcResult.fromRaw(raw);
  }
}