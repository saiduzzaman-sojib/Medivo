import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/models/role.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/expiry.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/stock_models.dart';
import '../stock_controller.dart';
import 'stock_style.dart';

Future<void> showBatchSheet(BuildContext context, StockItem item) =>
    showMedivoSheet<void>(context, (_) => BatchSheet(item: item));

class BatchSheet extends ConsumerStatefulWidget {
  const BatchSheet({super.key, required this.item});

  final StockItem item;

  @override
  ConsumerState<BatchSheet> createState() => _BatchSheetState();
}

class _BatchSheetState extends ConsumerState<BatchSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _validate() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(stockRepositoryProvider).validateBatch(widget.item.id);
      if (!mounted) return;
      refreshAfterChange(ref);
      if (r.ok) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Batch validated')));
      } else {
        setState(() {
          _busy = false;
          _error = r.userMessage;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Try again.';
      });
    }
  }

  Widget _row(MedivoColors c, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 4, child: Text(label, style: TextStyle(color: c.muted))),
            Expanded(
              flex: 6,
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final it = widget.item;
    final user = ref.watch(authControllerProvider).user;
    final days = it.daysLeft();
    final level = expiryLevel(days);
    final canValidate = user?.can(Permission.validateStock) ?? false;
    final needsValidation = !it.validated && !it.recalled && days > 0;

    Widget action;
    if (it.recalled) {
      action = Text('This batch was recalled.', style: TextStyle(color: c.danger));
    } else if (days <= 0) {
      action = Text('Expired stock cannot be validated.', style: TextStyle(color: c.danger));
    } else if (it.validated) {
      action = StatusChip(label: 'Validated', color: c.primary);
    } else if (canValidate) {
      action = FilledButton(
        onPressed: _busy ? null : _validate,
        child: _busy
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: c.muted),
              )
            : const Text('Validate this batch'),
      );
    } else {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Only a pharmacist can validate stock.', style: TextStyle(color: c.muted)),
          if (kDebugMode)
            TextButton(
              onPressed: _busy ? null : _validate,
              child: Text('Try anyway (debug builds only)',
                  style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700)),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(it.medicine.name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
              ),
              StatusChip(
                label: it.recalled ? 'Recalled' : expiryLabel(days),
                color: it.recalled ? c.danger : levelColor(c, level),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text('${it.batchCode} · pack of ${it.medicine.packSize}',
              style: TextStyle(color: c.muted)),
          const SizedBox(height: 10),
          _row(c, 'Branch', it.branch.name),
          _row(c, 'Quantity', '${it.quantity} units'),
          _row(c, 'Stock value', formatTaka(it.value)),
          _row(c, 'Expires', formatDate(it.expiresOn)),
          _row(c, 'Validated', it.validated ? 'Yes' : (needsValidation ? 'Not yet' : 'No')),
          const SizedBox(height: 14),
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
          action,
        ],
      ),
    );
  }
}