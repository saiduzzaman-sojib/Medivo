import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medivo/core/offline/cache_store.dart';
import 'package:medivo/core/offline/offline_cache_client.dart';
import 'package:medivo/core/offline/offline_status.dart';

String _b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
String _jwt(String sub) => '${_b64('{"alg":"HS256"}')}.${_b64('{"sub":"$sub"}')}.sig';

class _Harness {
  _Harness({int maxBytes = 200000}) {
    client = OfflineCacheClient(
      inner: MockClient((req) async {
        calls++;
        if (!online) throw http.ClientException('offline');
        return http.Response(
          reply,
          code,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      store: store,
      status: status,
      maxBytes: maxBytes,
      now: () => clock,
    );
  }

  late final OfflineCacheClient client;
  final MemoryCacheStore store = MemoryCacheStore();
  final OfflineStatus status = OfflineStatus();
  bool online = true;
  int code = 200;
  int calls = 0;
  String reply = '[{"id":1}]';
  DateTime clock = DateTime.utc(2026, 11, 24, 10);

  Future<http.Response> get(String path, {String? sub = 'u1'}) async {
    final r = http.Request('GET', Uri.parse('https://x.supabase.co$path'));
    if (sub != null) r.headers['Authorization'] = 'Bearer ${_jwt(sub)}';
    return http.Response.fromStream(await client.send(r));
  }

  Future<http.Response> post(String path, Map<String, dynamic> body, {String sub = 'u1'}) async {
    final r = http.Request('POST', Uri.parse('https://x.supabase.co$path'))
      ..headers['Authorization'] = 'Bearer ${_jwt(sub)}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    return http.Response.fromStream(await client.send(r));
  }
}

void main() {
  test('the user id is read from a token, and the public key gives none', () {
    expect(userIdFromAuthHeader('Bearer ${_jwt('abc')}'), 'abc');
    expect(userIdFromAuthHeader('bearer ${_jwt('abc')}'), 'abc');
    expect(userIdFromAuthHeader('Bearer ${_b64('{"alg":"x"}')}.${_b64('{"role":"anon"}')}.s'), isNull);
    expect(userIdFromAuthHeader('Bearer not-a-token'), isNull);
    expect(userIdFromAuthHeader(null), isNull);
  });

  test('a read is saved, and shown again when the server is unreachable', () async {
    final h = _Harness();
    final fresh = await h.get('/rest/v1/batches?select=*');
    expect(fresh.body, '[{"id":1}]');
    expect(h.status.state.offline, isFalse);

    h.online = false;
    h.clock = h.clock.add(const Duration(hours: 2));
    final saved = await h.get('/rest/v1/batches?select=*');
    expect(saved.statusCode, 200);
    expect(saved.body, '[{"id":1}]');
    expect(saved.headers['x-medivo-offline'], '1');
    expect(h.status.state.offline, isTrue);
    // Compare the moment in time, so the result does not depend on the time zone.
    expect(
      h.status.state.savedAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 24, 10)),
      isTrue,
    );
  });

  test('going back online clears the offline state', () async {
    final h = _Harness();
    await h.get('/rest/v1/batches');
    h.online = false;
    await h.get('/rest/v1/batches');
    expect(h.status.state.offline, isTrue);
    h.online = true;
    await h.get('/rest/v1/batches');
    expect(h.status.state.offline, isFalse);
  });

  test('without a saved answer the failure is passed on', () async {
    final h = _Harness()..online = false;
    await expectLater(h.get('/rest/v1/never-seen'), throwsA(isA<http.ClientException>()));
    expect(h.status.state.offline, isTrue);
    expect(h.status.state.savedAt, isNull);
  });

  test('every user has their own saved answers', () async {
    final h = _Harness();
    await h.get('/rest/v1/batches', sub: 'alice');
    h.online = false;
    await expectLater(h.get('/rest/v1/batches', sub: 'bob'), throwsA(isA<http.ClientException>()));
    expect((await h.get('/rest/v1/batches', sub: 'alice')).body, '[{"id":1}]');
  });

  test('signed-out requests are never saved', () async {
    final h = _Harness();
    await h.get('/rest/v1/batches', sub: null);
    expect(h.store.data, isEmpty);
  });

  test('only two read-only functions are saved, writes never are', () async {
    final h = _Harness();
    h.reply = '{"role":"pharmacist"}';
    await h.post('/rest/v1/rpc/my_access', {});
    h.reply = '{"ok":true}';
    await h.post('/rest/v1/rpc/add_batch', {'p_code': 'X'});
    await h.post('/rest/v1/rpc/approve_plan', {'p_plan': 'p'});
    expect(h.store.data.length, 1);

    h.online = false;
    expect((await h.post('/rest/v1/rpc/my_access', {})).body, '{"role":"pharmacist"}');
    await expectLater(
      h.post('/rest/v1/rpc/add_batch', {'p_code': 'X'}),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('a saved answer depends on the function arguments', () async {
    final h = _Harness();
    h.reply = '{"a":1}';
    await h.post('/rest/v1/rpc/sales_freshness', {'x': 1});
    h.online = false;
    await expectLater(
      h.post('/rest/v1/rpc/sales_freshness', {'x': 2}),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('an answer older than seven days is not shown', () async {
    final h = _Harness();
    await h.get('/rest/v1/batches');
    h.online = false;
    h.clock = h.clock.add(const Duration(days: 8));
    await expectLater(h.get('/rest/v1/batches'), throwsA(isA<http.ClientException>()));
  });

  test('a very large answer is not saved', () async {
    final h = _Harness(maxBytes: 10);
    h.reply = '[{"id":1,"name":"a long body that is over the limit"}]';
    await h.get('/rest/v1/batches');
    expect(h.store.data, isEmpty);
  });

  test('an error answer is passed on and not saved', () async {
    final h = _Harness();
    h.code = 401;
    h.reply = '{"message":"JWT expired"}';
    final r = await h.get('/rest/v1/batches');
    expect(r.statusCode, 401);
    expect(h.store.data, isEmpty);
    expect(h.status.state.offline, isFalse);
  });

  test('clearing the store removes every saved answer', () async {
    final h = _Harness();
    await h.get('/rest/v1/batches');
    await h.get('/rest/v1/medicines');
    expect(h.store.data.length, 2);
    await h.store.clear();
    h.online = false;
    await expectLater(h.get('/rest/v1/batches'), throwsA(isA<http.ClientException>()));
  });

  test('the oldest saved time wins while offline', () {
    final s = OfflineStatus();
    s.markOffline(DateTime.utc(2026, 11, 24, 10));
    s.markOffline(DateTime.utc(2026, 11, 24, 9));
    s.markOffline(DateTime.utc(2026, 11, 24, 11));
    expect(s.state.savedAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 24, 9)), isTrue);
    s.markOnline();
    expect(s.state.offline, isFalse);
    expect(s.state.savedAt, isNull);
  });
}