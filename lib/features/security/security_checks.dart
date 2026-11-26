import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models/role.dart';
import '../../core/network/rpc_result.dart';
import '../../core/network/supabase_providers.dart';
import '../../core/utils/format.dart';
import '../stock/stock_controller.dart';
import 'audit_controller.dart';
import 'data/acceptance_checks.dart';

class CheckDef {
  const CheckDef(this.id, this.title, this.how, {this.server = false});

  final String id;
  final String title;

  /// One plain sentence on what the check does.
  final String how;

  /// True when the check asks the server.
  final bool server;
}

const List<CheckDef> checkDefs = [
  CheckDef('AC-01', 'Expired and recalled stock is never planned',
      'Runs the planner on a test scenario that contains expired and recalled batches.'),
  CheckDef('AC-02', 'Orders and transfers are whole packs',
      'Checks every order and transfer from a test scenario against the pack size.'),
  CheckDef('AC-03', 'A stockout day is not zero demand',
      'Cleans a sales history that has a stockout day.'),
  CheckDef('AC-04', 'Files with personal columns are refused',
      'Offers a file with a patient column to the importer.'),
  CheckDef('AC-05', 'Oversized files are refused',
      'Offers a file just over 1 MB to the importer.'),
  CheckDef('AC-06', 'Repeated requests have a stable fingerprint',
      'Computes the fingerprint twice, then again with changed inputs.'),
  CheckDef('AC-07', 'Exports hold no personal fields',
      'Builds a sample approved export and looks at every field name.'),
  CheckDef('AC-08', 'The app and the database agree on permissions',
      'Asks the server for your permissions and compares them with the app.',
      server: true),
  CheckDef('AC-09', 'A role cannot do another role’s work',
      'Tries something your role must not do. The refusal is written to the audit log.',
      server: true),
  CheckDef('AC-10', 'Direct writes to the database are blocked',
      'Tries to insert a row straight into a table. It must be refused by a permission rule.',
      server: true),
  CheckDef('AC-11', 'Only your own organisation is visible',
      'Reads organisations and people and checks that all of them are yours.',
      server: true),
  CheckDef('AC-12', 'This session passed the second step',
      'Asks the sign-in service for the assurance level of this session.',
      server: true),
  CheckDef('AC-13', 'Expired stock is refused',
      'Tries to add a batch that expired yesterday. The refusal is audited.',
      server: true),
  CheckDef('AC-14', 'The audit chain is intact',
      'Asks the database to recompute every audit hash.',
      server: true),
];

class AcceptanceItem {
  const AcceptanceItem(this.def, {this.status, this.detail});

  final CheckDef def;
  final CheckStatus? status;
  final String? detail;
}

class AcceptanceState {
  const AcceptanceState({
    required this.items,
    this.running = false,
    this.finishedAt,
  });

  final List<AcceptanceItem> items;
  final bool running;
  final DateTime? finishedAt;

  int get passedCount => items.where((i) => i.status == CheckStatus.pass).length;
  int get failedCount => items.where((i) => i.status == CheckStatus.fail).length;
  int get errorCount => items.where((i) => i.status == CheckStatus.error).length;
  bool get allPassed => finishedAt != null && failedCount == 0 && errorCount == 0;
}

const String _zeroId = '00000000-0000-0000-0000-000000000000';

/// Runs the checks one after another against the live app and database.
class AcceptanceController extends AutoDisposeNotifier<AcceptanceState> {
  @override
  AcceptanceState build() => AcceptanceState(items: [for (final d in checkDefs) AcceptanceItem(d)]);

  Future<void> run() async {
    if (state.running) return;
    state = AcceptanceState(
      running: true,
      items: [for (final d in checkDefs) AcceptanceItem(d)],
    );
    for (var i = 0; i < checkDefs.length; i++) {
      CheckOutcome outcome;
      try {
        outcome = await _runOne(checkDefs[i].id);
      } catch (_) {
        outcome = couldNotRun('The check could not run. Check your connection and try again.');
      }
      final items = [...state.items];
      items[i] = AcceptanceItem(checkDefs[i], status: outcome.status, detail: outcome.detail);
      state = AcceptanceState(items: items, running: true);
    }
    state = AcceptanceState(items: state.items, finishedAt: DateTime.now());
    // The refusals above were written to the audit log.
    ref.invalidate(auditControllerProvider);
  }

  Future<CheckOutcome> _runOne(String id) async {
    final client = ref.read(supabaseClientProvider);
    final user = ref.read(authControllerProvider).user;
    final in30 = isoDate(DateTime.now().add(const Duration(days: 30)));

    switch (id) {
      case 'AC-01':
        return checkPlannerSkipsDeadStock();
      case 'AC-02':
        return checkWholePacks();
      case 'AC-03':
        return checkStockoutNotZero();
      case 'AC-04':
        return checkPersonalDataRejected();
      case 'AC-05':
        return checkOversizeRejected();
      case 'AC-06':
        return checkFingerprint();
      case 'AC-07':
        return checkExportClean();

      case 'AC-08':
        if (user == null) return couldNotRun('Not signed in.');
        final raw = await client.rpc('my_access');
        if (raw is! Map) return failed('The server did not return your access.');
        final perms = {for (final p in (raw['permissions'] as List? ?? const [])) p as String};
        return checkPermissionsMatch(role: user.role, server: perms);

      case 'AC-09':
        if (user == null) return couldNotRun('Not signed in.');
        final r = user.role == Role.branchManager
            ? RpcResult.fromRaw(await client.rpc('add_batch', params: {
                'p_medicine': _zeroId,
                'p_branch': _zeroId,
                'p_code': 'CHECK',
                'p_quantity': 1,
                'p_expires': in30,
              }))
            : RpcResult.fromRaw(await client.rpc('decide_transfer', params: {
                'p_transfer': _zeroId,
                'p_approve': true,
              }));
        return (!r.ok && r.status == 403)
            ? passed('Refused with 403: ${r.userMessage}')
            : failed('Expected a 403 refusal but got: ${r.userMessage}');

      case 'AC-10':
        if (user == null) return couldNotRun('Not signed in.');
        try {
          await client.from('batches').insert({
            'tenant_id': user.tenantId,
            'medicine_id': _zeroId,
            'branch_id': _zeroId,
            'batch_code': 'CHECK-DIRECT',
            'quantity': 1,
            'expires_on': in30,
          });
          return failed('A direct insert was accepted. This must never happen.');
        } on PostgrestException catch (e) {
          return e.code == '42501'
              ? passed('The database refused the direct write (permission denied).')
              : failed('Refused, but not by a permission rule: ${e.message}');
        }

      case 'AC-11':
        if (user == null) return couldNotRun('Not signed in.');
        final tenants = await client.from('tenants').select('id');
        final people = await client.from('profiles').select('tenant_id');
        final onlyMine = tenants.length == 1 &&
            tenants.first['id'] == user.tenantId &&
            people.every((p) => p['tenant_id'] == user.tenantId);
        return onlyMine
            ? passed('1 organisation and ${people.length} people are visible, all yours.')
            : failed('Data from another organisation is visible.');

      case 'AC-12':
        final aal = client.auth.mfa.getAuthenticatorAssuranceLevel();
        return aal.currentLevel == AuthenticatorAssuranceLevels.aal2
            ? passed('This session is verified with the second step.')
            : failed('This session has not passed the second step.');

      case 'AC-13':
        final yesterday = isoDate(DateTime.now().subtract(const Duration(days: 1)));
        final data = ref.read(stockControllerProvider).valueOrNull;
        final r = RpcResult.fromRaw(await client.rpc('add_batch', params: {
          'p_medicine': data?.medicines.firstOrNull?.id ?? _zeroId,
          'p_branch': data?.branches.firstOrNull?.id ?? _zeroId,
          'p_code': 'CHECK-EXPIRED',
          'p_quantity': 1,
          'p_expires': yesterday,
        }));
        return (!r.ok && (r.status == 422 || r.status == 403))
            ? passed('Refused with ${r.status}: ${r.userMessage}')
            : failed('Expired stock was not refused: ${r.userMessage}');

      case 'AC-14':
        final c = await ref.read(auditRepositoryProvider).verify();
        if (c.message != null) return couldNotRun(c.message!);
        return c.ok
            ? passed('${c.checked} entries checked, none altered.')
            : failed('The chain is broken at entry #${c.firstBadId}.');
    }
    return couldNotRun('Unknown check.');
  }
}

final acceptanceProvider =
    AutoDisposeNotifierProvider<AcceptanceController, AcceptanceState>(AcceptanceController.new);