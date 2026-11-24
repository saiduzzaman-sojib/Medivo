import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/permissions.dart';
import '../../core/models/role.dart';
import '../../core/theme/app_colors.dart';
import 'medivo_card.dart';
import 'status_chip.dart';

/// Placeholder body for a tab that is built in a later step.
/// It already shows exactly what the signed-in role may do on this page.
class ModulePage extends ConsumerWidget {
  const ModulePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.builtInStep,
    required this.permissions,
  });

  final String title;
  final String subtitle;
  final String builtInStep;
  final List<Permission> permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: c.muted)),
        const SizedBox(height: 18),
        MedivoCard(
          child: Row(
            children: [
              Icon(Icons.construction_rounded, color: c.warning),
              const SizedBox(width: 12),
              Expanded(child: Text('This page is built in $builtInStep.')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        MedivoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Your access here',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  StatusChip(label: user.role.label, color: c.secondary),
                ],
              ),
              const SizedBox(height: 8),
              for (final p in permissions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        user.role.can(p) ? Icons.check_circle_rounded : Icons.lock_rounded,
                        size: 20,
                        color: user.role.can(p) ? c.primary : c.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          p.label,
                          style: TextStyle(color: user.role.can(p) ? c.ink : c.muted),
                        ),
                      ),
                      StatusChip(
                        label: user.role.can(p) ? 'Allowed' : 'Not allowed',
                        color: user.role.can(p) ? c.primary : c.muted,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}