/// Every database function answers {"ok": true} or
/// {"ok": false, "status": 403|409|422, "message": "..."}.
/// This class turns that answer into something the screens can use.
class RpcResult {
  const RpcResult({
    required this.ok,
    this.status,
    this.message,
    this.data = const {},
  });

  final bool ok;
  final int? status;
  final String? message;
  final Map<String, dynamic> data;

  factory RpcResult.fromRaw(dynamic raw) {
    if (raw is! Map) {
      return const RpcResult(
        ok: false,
        status: 500,
        message: 'Unexpected response from the server.',
      );
    }
    final m = Map<String, dynamic>.from(raw);
    return RpcResult(
      ok: m['ok'] == true,
      status: (m['status'] as num?)?.toInt(),
      message: m['message'] as String?,
      data: m,
    );
  }

  /// Plain-language text for the person using the app.
  String get userMessage {
    if (ok) return 'Done.';
    if (message != null && message!.isNotEmpty) return message!;
    return switch (status) {
      403 => 'You are not allowed to do this.',
      409 => 'This changed. Refresh and try again.',
      422 => 'Please check the details.',
      _ => 'Something went wrong.',
    };
  }
}