import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/medivo_logo.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _hidePassword = true;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider.notifier).signIn(
          email: _email.text,
          password: _password.text,
          code: _code.text.trim(),
        );
  }

  void _fillDemo(String email) {
    _email.text = email;
    _password.text = 'Medivo@2026';
    _code.text = '482913';
    setState(() {});
  }

  InputDecoration _decoration(MedivoColors c, String label, IconData icon,
      {Widget? suffix}) {
    OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: w),
        );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: c.muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: c.raised,
      labelStyle: TextStyle(color: c.muted),
      border: border(c.line),
      enabledBorder: border(c.line),
      focusedBorder: border(c.primary, 1.6),
      errorBorder: border(c.danger),
      focusedErrorBorder: border(c.danger, 1.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: wide
          ? Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(flex: 4, child: _formArea(context, showBrand: false)),
              ],
            )
          : SafeArea(child: _formArea(context, showBrand: true)),
    );
  }

  Widget _formArea(BuildContext context, {required bool showBrand}) {
    final c = context.mc;
    final auth = ref.watch(authControllerProvider);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showBrand) ...[
                    const Center(child: MedivoLogo(size: 92, animate: true)),
                    const SizedBox(height: 14),
                    const Center(
                      child: Text('MEDIVO',
                          style: TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3)),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text('Pharmacy stock and expiry planner',
                          style: TextStyle(color: c.muted, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 28),
                  ],
                  Text('Sign in',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Use the account your administrator created for you.',
                      style: TextStyle(color: c.muted)),
                  const SizedBox(height: 22),
                  if (auth.error != null) ...[
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
                            child: Text(auth.error!,
                                style: TextStyle(
                                    color: c.danger, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    decoration: _decoration(c, 'Work email', Icons.mail_outline_rounded),
                    validator: (v) => _emailPattern.hasMatch((v ?? '').trim())
                        ? null
                        : 'Enter a valid email address.',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _hidePassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.password],
                    decoration: _decoration(
                      c,
                      'Password',
                      Icons.lock_outline_rounded,
                      suffix: IconButton(
                        tooltip: _hidePassword ? 'Show password' : 'Hide password',
                        icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: c.muted),
                        onPressed: () => setState(() => _hidePassword = !_hidePassword),
                      ),
                    ),
                    validator: (v) =>
                        (v ?? '').length >= 8 ? null : 'Use at least 8 characters.',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onFieldSubmitted: (_) => _submit(),
                    decoration:
                        _decoration(c, '6-digit verification code', Icons.shield_outlined),
                    validator: (v) =>
                        (v ?? '').trim().length == 6 ? null : 'Enter the 6-digit code.',
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: auth.loading ? null : _submit,
                    child: auth.loading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.6, color: c.muted),
                          )
                        : const Text('Sign in securely'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Biometric unlock turns on after your first secure sign-in.')),
                    ),
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('Unlock with fingerprint or face'),
                  ),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Accounts are managed by your administrator. Contact them to reset access.')),
                      ),
                      child: Text('Forgot password?',
                          style: TextStyle(
                              color: c.secondary, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.raised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_outlined, color: c.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Access follows your role. Every sign-in and approval is recorded in a signed audit trail.',
                            style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 18),
                    Text('Demo accounts (debug builds only)',
                        style: TextStyle(
                            color: c.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                            label: const Text('Pharmacist'),
                            onPressed: () => _fillDemo('pharmacist@medivo.test')),
                        ActionChip(
                            label: const Text('Purchaser'),
                            onPressed: () => _fillDemo('purchaser@medivo.test')),
                        ActionChip(
                            label: const Text('Branch manager'),
                            onPressed: () => _fillDemo('manager@medivo.test')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Left side on wide screens (web, tablet, desktop).
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    const features = <(IconData, String, String)>[
      (
        Icons.event_available_rounded,
        'Expiry-aware plans',
        'Orders and transfers that respect batch expiry and whole packs.'
      ),
      (
        Icons.admin_panel_settings_rounded,
        'Role-based approvals',
        'Pharmacist, purchaser and branch manager each see and do only their part.'
      ),
      (
        Icons.fact_check_rounded,
        'Signed audit trail',
        'Every decision is recorded and the chain can be verified.'
      ),
    ];
    return Container(
      color: MedivoColors.brandPanel,
      child: Stack(
        children: [
          Positioned(
            right: -140,
            top: -140,
            child: Container(
              width: 420,
              height: 420,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: MedivoColors.brandDeep),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const MedivoLogo(size: 104, animate: true),
                const SizedBox(height: 24),
                const Text('MEDIVO',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 5)),
                const SizedBox(height: 8),
                const Text('Pharmacy stock and expiry planner',
                    style: TextStyle(
                        color: Color(0xFF9FB3BF),
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 44),
                for (final f in features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3FA796).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(f.$1, color: const Color(0xFF3FA796)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.$2,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16)),
                              const SizedBox(height: 3),
                              Text(f.$3,
                                  style: const TextStyle(
                                      color: Color(0xFF8093A0), height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}