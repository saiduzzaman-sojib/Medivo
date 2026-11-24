import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';

/// Where the person is in the sign-in journey.
enum AuthStage { signedOut, needsMfaSetup, needsMfaChallenge, ready }

class AuthState {
  const AuthState({
    this.user,
    this.stage = AuthStage.signedOut,
    this.loading = false,
    this.initializing = false,
    this.error,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  final AppUser? user;
  final AuthStage stage;
  final bool loading;

  /// True only while the app checks for a saved session at start-up.
  final bool initializing;
  final String? error;
  final int failedAttempts;
  final DateTime? lockedUntil;
}

/// Data needed to show the QR code when a person sets up two-step verification.
class MfaEnrollment {
  const MfaEnrollment({
    required this.factorId,
    required this.uri,
    required this.secret,
  });

  final String factorId;
  final String uri;
  final String secret;
}

/// Real sign-in with Supabase Auth plus a mandatory second step (TOTP).
/// The client lockout only improves the experience. The real brake is the
/// server rate limit, and the role always comes from the server.
class AuthController extends Notifier<AuthState> {
  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 5);

  SupabaseClient get _client => Supabase.instance.client;

  @override
  AuthState build() {
    final sub = _client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut &&
          state.stage != AuthStage.signedOut) {
        state = const AuthState();
      }
    });
    ref.onDispose(sub.cancel);
    Future.microtask(_restore);
    return const AuthState(initializing: true);
  }

  Future<void> _restore() async {
    if (_client.auth.currentSession == null) {
      state = const AuthState();
      return;
    }
    await _afterPassword(silent: true);
  }

  Future<void> signIn({required String email, required String password}) async {
    final locked = state.lockedUntil;
    if (locked != null && DateTime.now().isBefore(locked)) {
      final mins = locked.difference(DateTime.now()).inMinutes + 1;
      state = AuthState(
        failedAttempts: state.failedAttempts,
        lockedUntil: locked,
        error: 'Too many attempts. Try again in $mins min.',
      );
      return;
    }

    state = AuthState(
      loading: true,
      failedAttempts: state.failedAttempts,
      lockedUntil: state.lockedUntil,
    );

    try {
      await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
    } on AuthException {
      _registerFailure();
      return;
    } catch (_) {
      state = const AuthState(
        error: 'Could not reach the server. Check your connection.',
      );
      return;
    }
    await _afterPassword();
  }

  /// One generic message so the screen never reveals which part was wrong.
  void _registerFailure() {
    final fails = state.failedAttempts + 1;
    final lock = fails >= maxAttempts ? DateTime.now().add(lockDuration) : null;
    state = AuthState(
      failedAttempts: lock != null ? 0 : fails,
      lockedUntil: lock,
      error: lock != null
          ? 'Too many attempts. Sign-in is locked for 5 minutes.'
          : 'The email or password is not correct.',
    );
  }

  /// After the password step: already verified (aal2), or set up, or challenge.
  Future<void> _afterPassword({bool silent = false}) async {
    try {
      final aal = _client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal.currentLevel == AuthenticatorAssuranceLevels.aal2) {
        await _loadAccess(silent: silent);
        return;
      }
      final factors = await _client.auth.mfa.listFactors();
      state = AuthState(
        stage: factors.totp.isEmpty
            ? AuthStage.needsMfaSetup
            : AuthStage.needsMfaChallenge,
      );
    } catch (_) {
      await _safeSignOut();
      state = AuthState(
        error: silent ? null : 'Could not check your verification. Try again.',
      );
    }
  }

  /// First time only: creates the authenticator entry and returns the QR data.
  Future<MfaEnrollment?> startEnrollment() async {
    try {
      final res = await _client.auth.mfa.enroll(
        factorType: FactorType.totp,
        issuer: 'MEDIVO',
        friendlyName: 'MEDIVO ${DateTime.now().millisecondsSinceEpoch}',
      );
      final totp = res.totp;
      if (totp == null) return null;
      return MfaEnrollment(factorId: res.id, uri: totp.uri, secret: totp.secret);
    } catch (_) {
      return null;
    }
  }

  /// Checks a 6-digit code. Returns null on success, or an error message.
  /// Used for set-up, for every sign-in, and later for a fresh check before
  /// a recall (when the person is already signed in).
  Future<String?> verifyCode({required String code, String? factorId}) async {
    try {
      var id = factorId;
      if (id == null) {
        final factors = await _client.auth.mfa.listFactors();
        if (factors.totp.isEmpty) return 'Two-step verification is not set up.';
        id = factors.totp.first.id;
      }
      final challenge = await _client.auth.mfa.challenge(factorId: id);
      await _client.auth.mfa.verify(
        factorId: id,
        challengeId: challenge.id,
        code: code,
      );
    } on AuthException {
      return 'That code is not correct or has expired.';
    } catch (_) {
      return 'Could not verify the code. Check your connection.';
    }
    if (state.stage != AuthStage.ready) await _loadAccess();
    return null;
  }

  /// Asks the database who this user is and what they may do.
  Future<void> _loadAccess({bool silent = false}) async {
    try {
      final data = await _client.rpc('my_access');
      if (data == null) {
        await _safeSignOut();
        state = AuthState(
          error: silent
              ? null
              : 'This account has no access yet. Contact your administrator.',
        );
        return;
      }
      final user = AppUser.fromAccess(
        Map<String, dynamic>.from(data as Map),
        email: _client.auth.currentUser?.email ?? '',
      );
      state = AuthState(user: user, stage: AuthStage.ready);
    } catch (_) {
      await _safeSignOut();
      state = AuthState(
        error: silent ? null : 'Could not load your access. Try again.',
      );
    }
  }

  Future<void> _safeSignOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
  }

  Future<void> signOut() async {
    state = const AuthState();
    await _safeSignOut();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);