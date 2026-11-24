import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/auth/auth_controller.dart';
import 'package:medivo/core/models/role.dart';

Future<void> _signIn(ProviderContainer c, String email, String pw, String code) {
  return c
      .read(authControllerProvider.notifier)
      .signIn(email: email, password: pw, code: code);
}

void main() {
  test('a valid account signs in with the right role and tenant', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await _signIn(c, 'manager@medivo.test', 'Medivo@2026', '482913');
    final s = c.read(authControllerProvider);
    expect(s.user?.role, Role.branchManager);
    expect(s.user?.tenantId, 'TENANT-A');
    expect(s.error, isNull);
  });

  test('a wrong code gives one generic error and no user', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await _signIn(c, 'manager@medivo.test', 'Medivo@2026', '000000');
    final s = c.read(authControllerProvider);
    expect(s.user, isNull);
    expect(s.error, 'The email, password or code is not correct.');
  });

  test('five failed attempts lock sign-in, even for a correct login', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    for (var i = 0; i < 5; i++) {
      await _signIn(c, 'manager@medivo.test', 'wrong-password', '482913');
    }
    expect(c.read(authControllerProvider).lockedUntil, isNotNull);

    await _signIn(c, 'manager@medivo.test', 'Medivo@2026', '482913');
    final s = c.read(authControllerProvider);
    expect(s.user, isNull);
    expect(s.error, contains('Too many attempts'));
  });
}