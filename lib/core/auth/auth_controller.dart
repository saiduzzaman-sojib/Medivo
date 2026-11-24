import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/role.dart';

class AuthState {
  const AuthState({
    this.user,
    this.loading = false,
    this.error,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  final AppUser? user;
  final bool loading;
  final String? error;
  final int failedAttempts;
  final DateTime? lockedUntil;
}

/// TEMPORARY sign-in used only until Step 3.
/// Step 3 replaces this class with Supabase Auth, a real second factor (TOTP)
/// and server-side lockout. The UI and the router do not change.
class AuthController extends Notifier<AuthState> {
  static const int maxAttempts = 5;
  static const Duration lockDuration = Duration(minutes: 5);

  // Demo directory. Real accounts live in the database, never in the app.
  static const _demoPassword = 'Medivo@2026';
  static const _demoCode = '482913';
  static const _demo = <String, (Role, String)>{
    'pharmacist@medivo.test': (Role.pharmacist, 'Nusrat Jahan'),
    'purchaser@medivo.test': (Role.purchaser, 'Imran Hossain'),
    'manager@medivo.test': (Role.branchManager, 'Rahim Uddin'),
  };

  @override
  AuthState build() => const AuthState();

  Future<void> signIn({
    required String email,
    required String password,
    required String code,
  }) async {
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
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final key = email.trim().toLowerCase();
    final match = _demo[key];
    final ok = match != null && password == _demoPassword && code == _demoCode;

    if (ok) {
      final found = match;
      state = AuthState(
        user: AppUser(
          id: 'demo-${found.$1.name}',
          name: found.$2,
          email: key,
          role: found.$1,
          tenantId: 'TENANT-A',
          tenantName: 'Dhanmondi Pharmacy Chain',
        ),
      );
      return;
    }

    // One generic message so the screen never reveals which part was wrong.
    final fails = state.failedAttempts + 1;
    final lock = fails >= maxAttempts ? DateTime.now().add(lockDuration) : null;
    state = AuthState(
      failedAttempts: lock != null ? 0 : fails,
      lockedUntil: lock,
      error: lock != null
          ? 'Too many attempts. Sign-in is locked for 5 minutes.'
          : 'The email, password or code is not correct.',
    );
  }

  void signOut() => state = const AuthState();
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);