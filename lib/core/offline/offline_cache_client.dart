import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'cache_store.dart';
import 'offline_status.dart';

/// Reads the signed-in user id (the "sub" claim) from an Authorization header.
/// Returns null for the public key, so nothing is saved for signed-out requests.
String? userIdFromAuthHeader(String? header) {
  if (header == null || !header.toLowerCase().startsWith('bearer ')) return null;
  final parts = header.substring(7).split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final m = jsonDecode(payload);
    final sub = m is Map ? m['sub'] : null;
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}

/// A network client that remembers the last good answer to every database read
/// and shows it when the server cannot be reached.
///  - Only reads are saved (GET, and two read-only database functions).
///  - Every user has their own saved answers.
///  - Writes are never saved and never replayed.
class OfflineCacheClient extends http.BaseClient {
  OfflineCacheClient({
    required http.Client inner,
    required CacheStore store,
    required OfflineStatus status,
    this.timeout = const Duration(seconds: 12),
    this.maxAge = const Duration(days: 7),
    this.maxBytes = 200000,
    DateTime Function()? now,
  })  : _inner = inner,
        _store = store,
        _status = status,
        _now = now ?? DateTime.now;

  final http.Client _inner;
  final CacheStore _store;
  final OfflineStatus _status;
  final Duration timeout;
  final Duration maxAge;
  final int maxBytes;
  final DateTime Function() _now;

  static const Set<String> _readOnlyFunctions = {'my_access', 'sales_freshness'};

  bool _cacheable(http.BaseRequest r) {
    final path = r.url.path;
    if (!path.contains('/rest/v1/')) return false;
    if (r.method == 'GET') return true;
    if (r.method == 'POST' && path.contains('/rest/v1/rpc/')) {
      return _readOnlyFunctions.contains(path.split('/').last);
    }
    return false;
  }

  String? _keyFor(http.BaseRequest r) {
    final uid = userIdFromAuthHeader(r.headers['Authorization'] ?? r.headers['authorization']);
    if (uid == null) return null;
    final body = r is http.Request ? sha256.convert(r.bodyBytes).toString() : '';
    return sha256.convert(utf8.encode('$uid|${r.method}|${r.url}|$body')).toString();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = _cacheable(request) ? _keyFor(request) : null;
    try {
      final pending = _inner.send(request);
      final res = key == null ? await pending : await pending.timeout(timeout);
      _status.markOnline();
      if (key == null || res.statusCode != 200) return res;

      final bytes = await res.stream.toBytes();
      if (bytes.length <= maxBytes) {
        try {
          await _store.write(
            key,
            jsonEncode({'t': _now().millisecondsSinceEpoch, 'b': utf8.decode(bytes, allowMalformed: true)}),
          );
        } catch (_) {
          // Saving is best effort. The answer is still returned.
        }
      }
      return http.StreamedResponse(
        Stream.value(bytes),
        res.statusCode,
        contentLength: bytes.length,
        request: res.request,
        headers: res.headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
    } catch (_) {
      if (key != null) {
        final saved = await _readFresh(key);
        if (saved != null) {
          _status.markOffline(saved.$1);
          final bytes = utf8.encode(saved.$2);
          return http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length,
            request: request,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'x-medivo-offline': '1',
            },
          );
        }
      }
      _status.markOffline();
      rethrow;
    }
  }

  Future<(DateTime, String)?> _readFresh(String key) async {
    try {
      final raw = await _store.read(key);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt());
      if (_now().difference(at) > maxAge) return null;
      return (at, m['b'] as String);
    } catch (_) {
      return null;
    }
  }

  @override
  void close() => _inner.close();
}