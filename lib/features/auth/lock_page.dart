import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/security/app_lock.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/medivo_logo.dart';

class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage> {
  bool _busy = false;
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  Future<void> _maybePrompt() async {
    final lock = ref.read(appLockProvider);
    if (!mounted || _prompted || !lock.checked || !lock.canUnlockWithBiometric) return;
    _prompted = true;
    await _unlock();
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    await ref.read(appLockProvider.notifier).unlockWithBiometric();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppLockState>(appLockProvider, (prev, next) {
      if (next.checked && !(prev?.checked ?? false)) _maybePrompt();
    });

    final c = context.mc;
    final lock = ref.watch(appLockProvider);
    final user = ref.watch(authControllerProvider).user;

    Widget body;
    if (!lock.checked) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (lock.canUnlockWithBiometric) {
      body = FilledButton.icon(
        onPressed: _busy ? null : _unlock,
        icon: const Icon(Icons.fingerprint_rounded),
        label: const Text('Unlock with fingerprint or face'),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            lock.available
                ? 'Biometric unlock is off for this account. Sign in again to continue.'
                : 'Biometric unlock is not available on this device. Sign in again to continue.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('Sign in again'),
          ),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: MedivoLogo(size: 84, animate: true)),
                  const SizedBox(height: 18),
                  Text('Locked for your security',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  if (user != null) ...[
                    const SizedBox(height: 6),
                    Text(user.name,
                        textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
                  ],
                  const SizedBox(height: 26),
                  body,
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                    child: Text('Sign out',
                        style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700)),
                  ),
                  if (kDebugMode)
                    TextButton(
                      onPressed: () => ref.read(appLockProvider.notifier).debugUnlock(),
                      child: Text('Continue without unlock (debug builds only)',
                          style: TextStyle(color: c.muted, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}