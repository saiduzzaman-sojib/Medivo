import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/rpc_result.dart';
import 'audit_entry.dart';

class ChainResult {
  const ChainResult({
    required this.ok,
    required this.checked,
    this.firstBadId,
    this.message,
  });

  final bool ok;
  final int checked;
  final int? firstBadId;
  final String? message;
}

/// Reads the audit log. The database only returns rows of the person's own
/// tenant, and only to roles that may view the audit log.
class AuditRepository {
  AuditRepository(this._client);

  final SupabaseClient _client;

  Future<List<AuditEntry>> fetch({
    required int offset,
    required int limit,
    bool deniedOnly = false,
  }) async {
    var query = _client.from('audit_log').select();
    if (deniedOnly) query = query.eq('ok', false);
    final rows = await query
        .order('id', ascending: false)
        .range(offset, offset + limit - 1);
    return [
      for (final r in rows) AuditEntry.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  /// Maps a user id to a full name, for showing who did what.
  Future<Map<String, String>> actorNames() async {
    final rows = await _client.from('profiles').select('id, full_name');
    return {
      for (final r in rows) r['id'] as String: r['full_name'] as String,
    };
  }

  /// The database recomputes every hash and checks the links between rows.
  Future<ChainResult> verify() async {
    final raw = await _client.rpc('verify_audit_chain');
    final r = RpcResult.fromRaw(raw);
    if (r.status != null) {
      return ChainResult(ok: false, checked: 0, message: r.userMessage);
    }
    return ChainResult(
      ok: r.ok,
      checked: (r.data['checked'] as num?)?.toInt() ?? 0,
      firstBadId: (r.data['first_bad_id'] as num?)?.toInt(),
    );
  }
}