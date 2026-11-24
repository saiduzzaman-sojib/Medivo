import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/app_user.dart';
import '../../core/security/app_lock.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/medivo_logo.dart';
import '../../shared/widgets/status_chip.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = <_Dest>[
  _Dest('Overview', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded),
  _Dest('Stock', Icons.inventory_2_outlined, Icons.inventory_2_rounded),
  _Dest('Forecast', Icons.show_chart_rounded, Icons.show_chart_rounded),
  _Dest('Plan', Icons.fact_check_outlined, Icons.fact_check_rounded),
  _Dest('Security', Icons.shield_outlined, Icons.shield_rounded),
];

/// Phone: bottom NavigationBar. Tablet, desktop and web: NavigationRail.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(appLockProvider).offer) _offerBiometric();
    });
  }

  Future<void> _offerBiometric() async {
    if (_asking || !mounted) return;
    _asking = true;
    final notifier = ref.read(appLockProvider.notifier);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn on biometric unlock?'),
        content: const Text(
          'Use your fingerprint or face to reopen MEDIVO quickly after it locks. '
          'You can change this later from the account menu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await notifier.setEnabled(true);
    } else {
      notifier.dismissOffer();
    }
    _asking = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppLockState>(appLockProvider, (prev, next) {
      if (next.offer && !(prev?.offer ?? false)) _offerBiometric();
    });

    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final shell = widget.shell;
    final c = context.mc;
    final wide = MediaQuery.sizeOf(context).width >= 860;
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);
    final header = _Header(user: user, showBrand: !wide);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              backgroundColor: c.surface,
              indicatorColor: c.raised,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: MedivoLogo(size: 44),
              ),
              destinations: [
                for (final d in _dests)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon, color: c.primary),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: c.line),
            Expanded(
              child: Column(children: [header, Expanded(child: shell)]),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [header, Expanded(child: shell)]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: go,
        destinations: [
          for (final d in _dests)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon, color: c.primary),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.user, required this.showBrand});

  final AppUser user;
  final bool showBrand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final lock = ref.watch(appLockProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Row(
        children: [
          if (showBrand) ...[
            const MedivoLogo(size: 36),
            const SizedBox(width: 10),
            const Text('MEDIVO',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 1.2)),
          ] else
            Text(user.tenantName, style: TextStyle(color: c.muted, fontWeight: FontWeight.w600)),
          const Spacer(),
          StatusChip(label: user.role.label, color: c.secondary),
          const SizedBox(width: 10),
          PopupMenuButton<String>(
            tooltip: 'Account',
            color: c.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (v) async {
              final lockCtl = ref.read(appLockProvider.notifier);
              if (v == 'out') {
                ref.read(authControllerProvider.notifier).signOut();
              } else if (v == 'lock') {
                lockCtl.lock();
              } else if (v == 'bio') {
                final ok = await lockCtl.setEnabled(!lock.enabled);
                if (!context.mounted || ok) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Biometric check was not completed.')),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
                    Text(user.email, style: TextStyle(color: c.muted, fontSize: 12)),
                    Text(user.tenantName, style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              if (lock.available)
                CheckedPopupMenuItem<String>(
                  value: 'bio',
                  checked: lock.enabled,
                  child: const Text('Biometric unlock'),
                ),
              const PopupMenuItem<String>(value: 'lock', child: Text('Lock now')),
              const PopupMenuItem<String>(value: 'out', child: Text('Sign out')),
            ],
            child: CircleAvatar(
              radius: 20,
              backgroundColor: c.secondary,
              child: Text(user.initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}