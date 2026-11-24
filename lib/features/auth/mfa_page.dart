import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/medivo_card.dart';
import '../../shared/widgets/medivo_logo.dart';

/// Two-step verification. Two modes:
///  - set-up (first sign-in): scan a QR code, then confirm with a code
///  - challenge (every sign-in): enter the current 6-digit code
class MfaPage extends ConsumerStatefulWidget {
  const MfaPage({super.key});

  @override
  ConsumerState<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends ConsumerState<MfaPage> {
  final _code = TextEditingController();
  MfaEnrollment? _enroll;
  bool _starting = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    if (ref.read(authControllerProvider).stage != AuthStage.needsMfaSetup) return;
    setState(() => _starting = true);
    final e = await ref.read(authControllerProvider.notifier).startEnrollment();
    if (!mounted) return;
    setState(() {
      _enroll = e;
      _starting = false;
      _error = e == null ? 'Could not start set-up. Please try again.' : null;
    });
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref
        .read(authControllerProvider.notifier)
        .verifyCode(code: code, factorId: _enroll?.factorId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err != null) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final setup = ref.watch(authControllerProvider).stage == AuthStage.needsMfaSetup;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: MedivoLogo(size: 72)),
                  const SizedBox(height: 18),
                  Text(
                    setup ? 'Set up two-step verification' : 'Enter your 6-digit code',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    setup
                        ? 'Scan the code with Google Authenticator, Microsoft Authenticator or Authy, then type the 6-digit number it shows.'
                        : 'Open your authenticator app and type the current code for MEDIVO.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  if (setup) ...[
                    if (_starting)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_enroll != null) ...[
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: _enroll!.uri,
                            size: 196,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      MedivoCard(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Cannot scan? Enter this key',
                                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    _enroll!.secret,
                                    style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.2),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy key',
                              icon: Icon(Icons.copy_rounded, color: c.secondary),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: _enroll!.secret));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Key copied')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                  ],
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.danger.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.danger.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: c.danger),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_error!,
                                style: TextStyle(
                                    color: c.danger, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!setup || _enroll != null) ...[
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 10),
                      decoration: InputDecoration(
                        hintText: '000000',
                        filled: true,
                        fillColor: c.raised,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: c.primary, width: 1.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.6, color: c.muted),
                            )
                          : Text(setup ? 'Verify and continue' : 'Verify'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                    child: Text('Use a different account',
                        style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700)),
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