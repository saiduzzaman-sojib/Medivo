import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medivo/features/plan/data/plan_providers.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/models/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../stock/data/stock_models.dart';
import '../../stock/stock_controller.dart';
import '../../stock/widgets/stock_style.dart';
import '../data/plan_export.dart';
import '../data/plan_models.dart';


InputDecoration _dec(MedivoColors c, String label, {String? hint}) {
  OutlineInputBorder b(Color color, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: c.raised,
    labelStyle: TextStyle(color: c.muted),
    border: b(c.line),
    enabledBorder: b(c.line),
    focusedBorder: b(c.primary, 1.6),
  );
}

Widget _busyIndicator(MedivoColors c) =>
    SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.6, color: c.muted));

// ---------------------------------------------------------------- approve

Future<void> showApproveSheet(BuildContext context, PlanRecord plan) =>
    showMedivoSheet<void>(context, (_) => ApproveSheet(plan: plan));

class ApproveSheet extends ConsumerStatefulWidget {
  const ApproveSheet({super.key, required this.plan});

  final PlanRecord plan;

  @override
  ConsumerState<ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends ConsumerState<ApproveSheet> {
  bool _handling = false;
  bool _busy = false;
  String? _error;

  Widget _check(MedivoColors c, String label, bool ok, {String? note}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: ok ? c.primary : c.warning, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (note != null) Text(note, style: TextStyle(color: c.muted)),
          ],
        ),
      );

  Future<void> _validateMoved(List<StockItem> toValidate) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    for (final item in toValidate) {
      final r = await safeRpc(() => ref.read(stockRepositoryProvider).validateBatch(item.id));
      if (!r.ok) {
        failure = '${item.batchCode}: ${r.userMessage}';
        break;
      }
    }
    if (!mounted) return;
    refreshPlanData(ref);
    setState(() {
      _busy = false;
      _error = failure;
    });
  }

  Future<void> _lock() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await safeRpc(
      () => ref.read(planRepositoryProvider).approve(widget.plan.id, widget.plan.version, _handling),
    );
    if (!mounted) return;
    refreshPlanData(ref);
    if (r.ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Plan locked as revision ${r.data['revision']}')),
      );
    } else {
      setState(() {
        _busy = false;
        _error = r.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final user = ref.watch(authControllerProvider).user;
    final transfers = ref.watch(transfersProvider(widget.plan.id)).valueOrNull ?? const [];
    final items = ref.watch(stockControllerProvider).valueOrNull?.items ?? const <StockItem>[];
    final byId = {for (final i in items) i.id: i};

    final moved = {
      for (final t in transfers)
        if (t.state != 'rejected' && byId[t.batchId] != null) t.batchId: byId[t.batchId]!,
    }.values.toList();
    final notValidated = [for (final i in moved) if (!i.validated) i];
    final reviewed = widget.plan.state == PlanState.reviewed;
    final canValidate = user?.can(Permission.validateStock) ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 14),
          const Text('Approve plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 4),
          Text('The pharmacist checks these before the plan is locked.',
              style: TextStyle(color: c.muted)),
          const SizedBox(height: 12),
          _check(c, 'A purchaser review was submitted', reviewed),
          _check(
            c,
            'Moved batches are validated',
            notValidated.isEmpty,
            note: '${moved.length - notValidated.length} of ${moved.length}',
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _handling,
            onChanged: _busy ? null : (v) => setState(() => _handling = v ?? false),
            title: const Text('Handling rules were followed'),
            subtitle: Text('Pharmacist-approved handling rules for storage and transfer.',
                style: TextStyle(color: c.muted, fontSize: 12.5)),
          ),
          if (_error != null) ...[const SizedBox(height: 8), ErrorBanner(_error!)],
          const SizedBox(height: 12),
          if (notValidated.isNotEmpty && canValidate)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: _busy ? null : () => _validateMoved(notValidated),
                child: Text('Validate ${notValidated.length} moved batch${notValidated.length == 1 ? '' : 'es'}'),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _lock,
            child: _busy ? _busyIndicator(c) : const Text('Lock plan'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- return

Future<void> showReturnSheet(BuildContext context, PlanRecord plan) =>
    showMedivoSheet<void>(context, (_) => ReturnSheet(plan: plan));

class ReturnSheet extends ConsumerStatefulWidget {
  const ReturnSheet({super.key, required this.plan});

  final PlanRecord plan;

  @override
  ConsumerState<ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends ConsumerState<ReturnSheet> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await safeRpc(() => ref.read(planRepositoryProvider).returnPlan(widget.plan.id, reason));
    if (!mounted) return;
    refreshPlanData(ref);
    if (r.ok) {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Plan returned')));
    } else {
      setState(() {
        _busy = false;
        _error = r.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 14),
          const Text('Return plan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 4),
          Text('The reason is written to the audit log.', style: TextStyle(color: c.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            maxLength: 160,
            decoration: _dec(c, 'Reason', hint: 'for example batch counts look wrong'),
          ),
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? _busyIndicator(c) : const Text('Return plan'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- recall

Future<void> showRecallSheet(BuildContext context, StockItem item) =>
    showMedivoSheet<void>(context, (_) => RecallSheet(item: item));

class RecallSheet extends ConsumerStatefulWidget {
  const RecallSheet({super.key, required this.item});

  final StockItem item;

  @override
  ConsumerState<RecallSheet> createState() => _RecallSheetState();
}

class _RecallSheetState extends ConsumerState<RecallSheet> {
  final _reason = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    final code = _code.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason for the recall.');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = 'Enter your 6-digit verification code.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    // A recall needs a code typed just now, not only at sign-in.
    final bad = await ref.read(authControllerProvider.notifier).verifyCode(code: code);
    if (!mounted) return;
    if (bad != null) {
      _code.clear();
      setState(() {
        _busy = false;
        _error = bad;
      });
      return;
    }

    final r = await safeRpc(() => ref.read(planRepositoryProvider).recallBatch(widget.item.id, reason));
    if (!mounted) return;
    refreshPlanData(ref);
    if (r.ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Batch ${widget.item.batchCode} recalled')),
      );
    } else {
      _code.clear();
      setState(() {
        _busy = false;
        _error = r.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final it = widget.item;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 14),
          Text('Recall ${it.batchCode}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 4),
          Text(
            '${it.medicine.name} at ${it.branch.name}, ${it.quantity} units. The batch is removed from every plan and its pending transfers are rejected.',
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            maxLength: 160,
            decoration: _dec(c, 'Reason', hint: 'for example supplier recall notice'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8),
            decoration: _dec(c, 'Verification code', hint: '000000'),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: Colors.white),
            onPressed: _busy ? null : _submit,
            child: _busy ? _busyIndicator(c) : const Text('Approve recall'),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- export

Future<void> showExportSheet(BuildContext context, PlanRecord plan) =>
    showMedivoSheet<void>(context, (_) => ExportSheet(plan: plan));

class ExportSheet extends ConsumerWidget {
  const ExportSheet({super.key, required this.plan});

  final PlanRecord plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.mc;
    final data = ref.watch(stockControllerProvider).valueOrNull;
    final transfers = ref.watch(transfersProvider(plan.id)).valueOrNull ?? const [];

    final text = buildPlanExport(
      plan: plan,
      transfers: transfers,
      medicineNames: {for (final m in data?.medicines ?? const <Medicine>[]) m.id: m.name},
      branchNames: {for (final b in data?.branches ?? const <Branch>[]) b.id: b.name},
      batchCodes: {for (final i in data?.items ?? const <StockItem>[]) i.id: i.batchCode},
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('Approved export',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
              ),
              StatusChip(label: 'Revision ${plan.revision}', color: c.primary),
            ],
          ),
          const SizedBox(height: 4),
          Text('Bound to the input fingerprint, the model and policy versions and the plan revision.',
              style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: text));
              messenger.showSnackBar(const SnackBar(content: Text('Export copied')));
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- outcome

Future<void> showOutcomeSheet(BuildContext context, PlanRecord plan, int cycleNumber) =>
    showMedivoSheet<void>(context, (_) => OutcomeSheet(plan: plan, cycleNumber: cycleNumber));

class OutcomeSheet extends ConsumerStatefulWidget {
  const OutcomeSheet({super.key, required this.plan, required this.cycleNumber});

  final PlanRecord plan;
  final int cycleNumber;

  @override
  ConsumerState<OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends ConsumerState<OutcomeSheet> {
  late final TextEditingController _label =
      TextEditingController(text: 'Cycle ${widget.cycleNumber}');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Enter a name for this cycle.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await safeRpc(
      () => ref.read(planRepositoryProvider).recordOutcome(
            planId: widget.plan.id,
            label: label,
            baseline: widget.plan.riskBefore ?? 0,
            planCost: widget.plan.riskAfter ?? 0,
          ),
    );
    if (!mounted) return;
    refreshPlanData(ref);
    if (r.ok) {
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Outcome recorded')));
    } else {
      setState(() {
        _busy = false;
        _error = r.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final p = widget.plan;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 14),
          const Text('Record outcome', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 4),
          Text('Expiry loss without the plan compared with the plan.',
              style: TextStyle(color: c.muted)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text('Without the plan', style: TextStyle(color: c.muted))),
              Text(formatTaka(p.riskBefore ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('With the plan', style: TextStyle(color: c.muted))),
              Text(formatTaka(p.riskAfter ?? 0), style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          TextField(controller: _label, maxLength: 40, decoration: _dec(c, 'Cycle name')),
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? _busyIndicator(c) : const Text('Record outcome'),
          ),
        ],
      ),
    );
  }
}