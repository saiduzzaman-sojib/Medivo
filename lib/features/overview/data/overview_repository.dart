import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/format.dart';

class OverviewRepository {
  OverviewRepository(this._client);

  final SupabaseClient _client;

  /// Recorded sales for one medicine at one branch. The database only returns
  /// rows of the person's own tenant.
  Future<List<Map<String, dynamic>>> salesRows({
    required String medicineId,
    required String branchId,
    required int days,
  }) async {
    final from = isoDate(DateTime.now().subtract(Duration(days: days)));
    final rows = await _client
        .from('medicine_sales')
        .select('day, quantity, flag')
        .eq('medicine_id', medicineId)
        .eq('branch_id', branchId)
        .gte('day', from)
        .order('day', ascending: true);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }
}