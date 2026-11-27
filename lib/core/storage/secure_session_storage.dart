import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the sign-in session in the device's secure storage
/// (iOS Keychain, Android Keystore) instead of plain preferences.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Writes run one after another, so two session refreshes can never
  /// write to the Keychain at the same moment.
  Future<void> _queue = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() job) {
    final next = _queue.then((_) => job());
    _queue = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() =>
      _storage.containsKey(key: supabasePersistSessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: supabasePersistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) => _enqueue(() async {
        try {
          await _storage.write(key: supabasePersistSessionKey, value: persistSessionString);
        } on PlatformException {
          // The Keychain says the item already exists. Remove the old one and write again.
          await _storage.delete(key: supabasePersistSessionKey);
          await _storage.write(key: supabasePersistSessionKey, value: persistSessionString);
        }
      });

  @override
  Future<void> removePersistedSession() =>
      _enqueue(() => _storage.delete(key: supabasePersistSessionKey));
}