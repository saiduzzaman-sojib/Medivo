import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_controller.dart';
import 'biometric_service.dart';

class LockConfig {
  const LockConfig._();

  /// Lock after this long without touching the screen.
  static const Duration idleTimeout = Duration(minutes: 5);

  /// Lock when the app was in the background longer than this.
  static const Duration backgroundGrace = Duration(seconds: 60);
}

class AppLockState {
  const AppLockState({
    this.locked = false,
    this.checked = false,
    this.available = false,
    this.enabled = false,
    this.offer = false,
  });

  /// The screen is hidden behind the lock page.
  final bool locked;

  /// The biometric check at start-up has finished.
  final bool checked;

  /// The phone has biometrics set up.
  final bool available;

  /// The person turned biometric unlock on.
  final bool enabled;

  /// Ask the person once whether to turn biometric unlock on.
  final bool offer;

  bool get canUnlockWithBiometric => available && enabled;

  AppLockState copyWith({
    bool? locked,
    bool? checked,
    bool? available,
    bool? enabled,
    bool? offer,
  }) {
    return AppLockState(
      locked: locked ?? this.locked,
      checked: checked ?? this.checked,
      available: available ?? this.available,
      enabled: enabled ?? this.enabled,
      offer: offer ?? this.offer,
    );
  }
}

final biometricServiceProvider = Provider<BiometricService>((ref) => BiometricService());

/// Rules:
///  - A saved session found at start-up is locked until the person unlocks it.
///  - Idle time and long background time lock the app.
///  - Without a working biometric, the only way back in is a full sign-in.
class AppLockController extends Notifier<AppLockState> {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _userId;

  String _key(String id) => 'medivo_biometric_$id';

  @override
  AppLockState build() {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      final wasReady = prev?.stage == AuthStage.ready;
      if (next.stage == AuthStage.ready && !wasReady) {
        _onReady(next);
      } else if (next.stage != AuthStage.ready && wasReady) {
        _userId = null;
        state = const AppLockState();
      }
    });
    return const AppLockState();
  }

  Future<void> _onReady(AuthState auth) async {
    final user = auth.user!;
    _userId = user.id;
    final restored = auth.restored;

    // Lock at once on a cold start, before anything is shown.
    state = AppLockState(locked: restored);

    final available = await ref.read(biometricServiceProvider).isAvailable();
    var enabled = false;
    if (available) {
      try {
        enabled = (await _store.read(key: _key(user.id))) == '1';
      } catch (_) {
        enabled = false;
      }
    }
    if (_userId != user.id) return; // signed out in the meantime
    state = state.copyWith(
      checked: true,
      available: available,
      enabled: enabled,
      offer: !restored && available && !enabled,
    );
  }

  void lock() {
    if (ref.read(authControllerProvider).stage != AuthStage.ready) return;
    if (state.locked) return;
    state = state.copyWith(locked: true);
  }

  Future<bool> unlockWithBiometric() async {
    if (!state.canUnlockWithBiometric) return false;
    final ok = await ref.read(biometricServiceProvider).authenticate('Unlock MEDIVO');
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  /// Turning it on needs one successful biometric check first.
  Future<bool> setEnabled(bool value) async {
    final id = _userId;
    if (id == null) return false;
    if (value) {
      final ok = await ref
          .read(biometricServiceProvider)
          .authenticate('Turn on biometric unlock for MEDIVO');
      if (!ok) return false;
    }
    try {
      await _store.write(key: _key(id), value: value ? '1' : '0');
    } catch (_) {
      return false;
    }
    state = state.copyWith(enabled: value, offer: false);
    return true;
  }

  void dismissOffer() => state = state.copyWith(offer: false);

  /// Only for development on simulators and the web.
  void debugUnlock() {
    if (kDebugMode) state = state.copyWith(locked: false);
  }
}

final appLockProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);