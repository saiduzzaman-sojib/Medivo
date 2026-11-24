import '../../../core/models/permission_key.dart';

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actorId,
    required this.actorRole,
    required this.action,
    required this.ok,
    required this.detail,
    required this.prevHash,
    required this.rowHash,
    required this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> j) {
    return AuditEntry(
      id: (j['id'] as num).toInt(),
      actorId: j['actor_id'] as String?,
      actorRole: j['actor_role'] as String?,
      action: j['action'] as String,
      ok: j['ok'] as bool,
      detail: Map<String, dynamic>.from((j['detail'] as Map?) ?? const {}),
      prevHash: j['prev_hash'] as String,
      rowHash: j['row_hash'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
    );
  }

  final int id;
  final String? actorId;
  final String? actorRole;
  final String action;
  final bool ok;
  final Map<String, dynamic> detail;
  final String prevHash;
  final String rowHash;
  final DateTime createdAt;

  /// "Branch manager" instead of "branch_manager".
  String get roleLabel {
    final key = actorRole;
    if (key == null) return 'Unknown role';
    return roleFromKey(key)?.label ?? key;
  }
}