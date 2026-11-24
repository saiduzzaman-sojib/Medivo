import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';

class AuthState {
  const AuthState({
    this.user,
    this.loading = false,
    this.initializing = false,
    this.error,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  final AppUser? user;
  final bool loading;

  /// True only while the app checks for a saved session at start-up.
  final bool initializing;
  final String? error;
  final int failedAttempts;
  final DateTime? lockedUntil;
}

/// Real sign-in with Supabase Auth.
/// The client lockout below only improves the experience. The real brake is
/// the server rate limit in Supabase, and the role always comes from the server.
class AuthController extends Notifier<AuthState> {
  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 5);

  SupabaseClient get _client => Supabase.instance.client;

  @override
  AuthState build() {
    final sub = _client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut && state.user != null) {
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
    await _loadAccess(silent: true);
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
    await _loadAccess();
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
      state = AuthState(user: user);
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