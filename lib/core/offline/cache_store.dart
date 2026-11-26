import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where saved answers live.
abstract class CacheStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);

  /// Removes every saved answer.
  Future<void> clear();
}

/// Saved answers are kept in the device's secure storage
/// (iOS Keychain, Android Keystore), never in plain files.
class SecureCacheStore implements CacheStore {
  SecureCacheStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _prefix = 'medivo_cache_';
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: '$_prefix$key');

  @override
  Future<void> write(String key, String value) => _s.write(key: '$_prefix$key', value: value);

  @override
  Future<void> clear() async {
    final all = await _s.readAll();
    for (final k in all.keys) {
      if (k.startsWith(_prefix)) await _s.delete(key: k);
    }
  }
}

/// For tests.
class MemoryCacheStore implements CacheStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> clear() async => data.clear();
}