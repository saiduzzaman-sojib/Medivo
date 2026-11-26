import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/offline/cache_store.dart';
import 'core/offline/offline_cache_client.dart';
import 'core/offline/offline_status.dart';
import 'core/router/app_router.dart';
import 'core/storage/secure_session_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/idle_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _ConfigMissingApp());
    return;
  }

  final cache = SecureCacheStore();
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
    httpClient: OfflineCacheClient(
      inner: http.Client(),
      store: cache,
      status: offlineStatus,
    ),
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );

  // Signing out removes every saved answer from this device.
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedOut) {
      unawaited(cache.clear());
      offlineStatus.markOnline();
    }
  });

  runApp(const ProviderScope(child: MedivoApp()));
}

/// App-wide theme mode. Dark by default, switchable later from Settings.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

class MedivoApp extends ConsumerWidget {
  const MedivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MEDIVO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => IdleGuard(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _ConfigMissingApp extends StatelessWidget {
  const _ConfigMissingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Missing configuration.\n\nRun the app with:\nflutter run --dart-define-from-file=env/dev.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}