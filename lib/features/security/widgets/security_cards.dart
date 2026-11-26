import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/medivo_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../overview/widgets/overview_cards.dart';
import '../data/acceptance_checks.dart';
import '../security_checks.dart';

class AcceptanceCard extends ConsumerWidget {
  const AcceptanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final s = ref.watch(acceptanceProvider);

    (String, Color) chip(AcceptanceItem i) {
      return switch (i.status) {
        CheckStatus.pass => ('Pass', c.primary),
        CheckStatus.fail => ('Fail', c.danger),
        CheckStatus.error => ('Could not run', c.warning),
        null => (s.running ? 'Waiting' : 'Not run', c.muted),
      };
    }

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle(
            'Acceptance checks',
            subtitle:
                'Each check runs against the live app and database. Checks marked Server ask the database; refused attempts are written to the audit log.',
            trailing: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: s.running ? null : () => ref.read(acceptanceProvider.notifier).run(),
              child: s.running
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: c.muted),
                    )
                  : const Text('Run all'),
            ),
          ),
          if (s.finishedAt != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusChip(label: '${s.passedCount} passed', color: c.primary),
                if (s.failedCount > 0) StatusChip(label: '${s.failedCount} failed', color: c.danger),
                if (s.errorCount > 0)
                  StatusChip(label: '${s.errorCount} could not run', color: c.warning),
                Text('at ${formatDateTime(s.finishedAt!)}',
                    style: TextStyle(color: c.muted, fontSize: 12.5)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          for (final i in s.items)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(i.def.id,
                                style: TextStyle(
                                    color: c.muted,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w700)),
                            if (i.def.server) ...[
                              const SizedBox(width: 8),
                              StatusChip(label: 'Server', color: c.secondary),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(i.def.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          i.detail ?? i.def.how,
                          style: TextStyle(
                            color: i.status == CheckStatus.fail ? c.danger : c.muted,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusChip(label: chip(i).$1, color: chip(i).$2),
                ],
              ),
            ),
          if (s.allPassed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'All ${s.items.length} checks passed for this role. Sign in as each role and run them again.',
                style: TextStyle(color: c.primary, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class RecoveryCard extends StatelessWidget {
  const RecoveryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.mc;

    Widget point(IconData icon, String title, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: c.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(text, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardTitle(
            'Recovery readiness',
            subtitle: 'What protects the data if something goes wrong. The steps are in docs/BACKUP_RESTORE.md.',
          ),
          const SizedBox(height: 6),
          point(
            Icons.backup_rounded,
            'Backups',
            'Paid plans are backed up daily by the database provider. A free plan has no automatic backups, so take your own dump and keep it off-site.',
          ),
          point(
            Icons.restore_rounded,
            'Restore drill',
            'Restore into a new project, then run the restore report and compare it with production. Do this before the pilot and after every big change.',
          ),
          point(
            Icons.lock_clock_rounded,
            'What a restore must keep',
            'Approved plan revisions, transfers, outcomes and the audit chain. The chain check shows if anything was altered.',
          ),
          point(
            Icons.undo_rounded,
            'Rollback',
            'Keep the previous app build. Database changes only move forward, so a rollback means restoring from a backup.',
          ),
        ],
      ),
    );
  }
}