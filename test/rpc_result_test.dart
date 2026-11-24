import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/network/rpc_result.dart';

void main() {
  test('a success answer is ok', () {
    final r = RpcResult.fromRaw({'ok': true, 'id': 'x'});
    expect(r.ok, isTrue);
    expect(r.status, isNull);
    expect(r.data['id'], 'x');
  });

  test('a denied answer keeps the status and the server message', () {
    final r = RpcResult.fromRaw({
      'ok': false,
      'status': 403,
      'message': 'Your role cannot add batches.',
    });
    expect(r.ok, isFalse);
    expect(r.status, 403);
    expect(r.userMessage, 'Your role cannot add batches.');
  });

  test('a missing message falls back to plain text per status', () {
    expect(RpcResult.fromRaw({'ok': false, 'status': 409}).userMessage,
        'This changed. Refresh and try again.');
    expect(RpcResult.fromRaw({'ok': false, 'status': 422}).userMessage,
        'Please check the details.');
  });

  test('an unexpected answer is treated as a failure', () {
    final r = RpcResult.fromRaw('not a map');
    expect(r.ok, isFalse);
    expect(r.status, 500);
  });
}