import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/app_user.dart';
import '../../core/models/role.dart';
import '../../core/security/app_lock.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/medivo_card.dart';
import '../../shared/widgets/status_chip.dart';
import 'audit_controller.dart';
import 'data/audit_entry.dart';

class SecurityPage extends ConsumerWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();
    final canAudit = user.can(Permission.viewAudit);

    return RefreshIndicator(
      onRefresh: () async {
        if (canAudit) await ref.read(auditControllerProvider.notifier).refresh();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Security and audit',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Your session and a tamper-evident record of every action.',
              style: TextStyle(color: c.muted)),
          const SizedBox(height: 18),
          _SessionCard(user: user),
          const SizedBox(height: 14),
          if (canAudit)
            const _AuditSection()
          else
            MedivoCard(
              child: Row(
                children: [
                  Icon(Icons.lock_rounded, color: c.muted),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Your role cannot view the audit log.')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final lock = ref.watch(appLockProvider);
    final biometric = !lock.available
        ? 'Not available on this device'
        : (lock.enabled ? 'On' : 'Off');

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: Text(label, style: TextStyle(color: c.muted))),
              Expanded(
                flex: 5,
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Your session',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              StatusChip(label: 'Protected', color: c.primary),
            ],
          ),
          const SizedBox(height: 6),
          row('Role', user.role.label),
          row('Organisation', user.tenantName),
          row('Two-step verification', 'Required at every sign-in'),
          row('Auto-lock',
              '${humanDuration(LockConfig.idleTimeout)} idle, ${humanDuration(LockConfig.backgroundGrace)} in background'),
          row('Biometric unlock', biometric),
          row('Session storage', 'Secure storage on this device'),
        ],
      ),
    );
  }
}

class _AuditSection extends ConsumerWidget {
  const _AuditSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final a = ref.watch(auditControllerProvider);
    final v = ref.watch(verifyControllerProvider);
    final controller = ref.read(auditControllerProvider.notifier);

    Widget verifyBanner() {
      if (v.error != null) {
        return _Banner(color: c.danger, icon: Icons.error_outline_rounded, text: v.error!);
      }
      final r = v.result;
      if (r == null) return const SizedBox.shrink();
      if (r.ok) {
        return _Banner(
          color: c.primary,
          icon: Icons.verified_rounded,
          text: 'Chain intact. ${r.checked} entries checked.',
        );
      }
      return _Banner(
        color: c.danger,
        icon: Icons.gpp_bad_rounded,
        text: r.message ??
            'The chain is broken at entry #${r.firstBadId}. Entries may have been altered.',
      );
    }

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Audit log',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Each entry is linked to the one before it. The log can only be added to, never edited or deleted.',
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: v.running
                ? null
                : () => ref.read(verifyControllerProvider.notifier).run(),
            icon: v.running
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Icon(Icons.verified_user_outlined),
            label: const Text('Verify audit chain'),
          ),
          verifyBanner(),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: !a.deniedOnly,
                onSelected: (_) => controller.setDeniedOnly(false),
              ),
              ChoiceChip(
                label: const Text('Denied only'),
                selected: a.deniedOnly,
                onSelected: (_) => controller.setDeniedOnly(true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (a.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(a.error!, style: TextStyle(color: c.danger)),
            ),
          if (a.entries.isEmpty && !a.loading && a.error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  a.deniedOnly ? 'No denied actions yet.' : 'Nothing recorded yet.',
                  style: TextStyle(color: c.muted),
                ),
              ),
            ),
          for (final e in a.entries)
            _EntryTile(
              entry: e,
              actor: a.names[e.actorId] ?? 'Unknown user',
              onTap: () => _showEntry(context, e, a.names[e.actorId] ?? 'Unknown user'),
            ),
          if (a.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (a.hasMore && !a.loading && a.entries.isNotEmpty)
            TextButton(
              onPressed: controller.loadMore,
              child: Text('Load more',
                  style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.actor, required this.onTap});

  final AuditEntry entry;
  final String actor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            Icon(
              entry.ok ? Icons.check_circle_rounded : Icons.block_rounded,
              color: entry.ok ? c.primary : c.danger,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sentenceCase(entry.action),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '$actor · ${entry.roleLabel} · ${formatDateTime(entry.createdAt)}',
                    style: TextStyle(color: c.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusChip(
              label: entry.ok ? 'Recorded' : 'Denied',
              color: entry.ok ? c.primary : c.danger,
            ),
          ],
        ),
      ),
    );
  }
}

void _showEntry(BuildContext context, AuditEntry e, String actor) {
  final c = context.mc;
  const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
  final pretty = const JsonEncoder.withIndent('  ').convert(e.detail);

  Widget field(String label, String value, {bool copy = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: Text(label, style: TextStyle(color: c.muted))),
            Expanded(
              flex: 6,
              child: SelectableText(value,
                  style: copy ? mono : const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (copy)
              IconButton(
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.copy_rounded, size: 18, color: c.secondary),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
              ),
          ],
        ),
      );

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(sentenceCase(e.action),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                StatusChip(
                  label: e.ok ? 'Recorded' : 'Denied',
                  color: e.ok ? c.primary : c.danger,
                ),
              ],
            ),
            const SizedBox(height: 8),
            field('Entry', '#${e.id}'),
            field('Who', '$actor (${e.roleLabel})'),
            field('When', formatDateTime(e.createdAt)),
            field('Hash', e.rowHash, copy: true),
            field('Previous hash', e.prevHash, copy: true),
            const SizedBox(height: 10),
            Text('Details', style: TextStyle(color: c.muted)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(pretty, style: mono),
            ),
          ],
        ),
      ),
    ),
  );
}