import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/auth/auth_controller.dart';
import 'package:medivo/core/router/app_router.dart';

void main() {
  test('while checking a saved session everyone waits on the splash', () {
    const s = AuthState(initializing: true);
    expect(redirectFor(s, '/login'), '/splash');
    expect(redirectFor(s, '/splash'), isNull);
  });

  test('signed-out people can only see the login page', () {
    const s = AuthState();
    expect(redirectFor(s, '/home'), '/login');
    expect(redirectFor(s, '/plan'), '/login');
    expect(redirectFor(s, '/login'), isNull);
  });

  test('a correct password alone does not open the app', () {
    for (final stage in [AuthStage.needsMfaSetup, AuthStage.needsMfaChallenge]) {
      final s = AuthState(stage: stage);
      expect(redirectFor(s, '/home'), '/mfa');
      expect(redirectFor(s, '/security'), '/mfa');
      expect(redirectFor(s, '/mfa'), isNull);
    }
  });

  test('after the second step the person enters the app', () {
    const s = AuthState(stage: AuthStage.ready);
    expect(redirectFor(s, '/login'), '/home');
    expect(redirectFor(s, '/mfa'), '/home');
    expect(redirectFor(s, '/plan'), isNull);
  });
}