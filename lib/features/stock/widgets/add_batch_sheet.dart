import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../data/stock_models.dart';
import '../stock_controller.dart';
import 'stock_style.dart';

Future<void> showAddBatchSheet(BuildContext context, StockData data) =>
    showMedivoSheet<void>(context, (_) => AddBatchSheet(data: data));

class AddBatchSheet extends ConsumerStatefulWidget {
  const AddBatchSheet({super.key, required this.data});

  final StockData data;

  @override
  ConsumerState<AddBatchSheet> createState() => _AddBatchSheetState();
}

class _AddBatchSheetState extends ConsumerState<AddBatchSheet> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _qty = TextEditingController();
  Medicine? _med;
  Branch? _branch;
  DateTime? _expires;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires ?? now.add(const Duration(days: 90)),
      // Debug builds may pick a past date, to see the server refuse it (422).
      firstDate: kDebugMode
          ? now.subtract(const Duration(days: 365))
          : now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expires = picked);
  }

  Future<void> _submit() async {
    final formOk = _form.currentState!.validate();
    if (_med == null || _branch == null || _expires == null) {
      setState(() => _error = 'Choose a medicine, a branch and an expiry date.');
      return;
    }
    if (!formOk) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(stockRepositoryProvider).addBatch(
            medicineId: _med!.id,
            branchId: _branch!.id,
            code: _code.text.trim(),
            quantity: int.parse(_qty.text.trim()),
            expires: _expires!,
          );
      if (!mounted) return;
      refreshAfterChange(ref);
      if (r.ok) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Batch added')));
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

  InputDecoration _dec(MedivoColors c, String label) {
    OutlineInputBorder b(Color color, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: w),
        );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: c.raised,
      labelStyle: TextStyle(color: c.muted),
      border: b(c.line),
      enabledBorder: b(c.line),
      focusedBorder: b(c.primary, 1.6),
      errorBorder: b(c.danger),
      focusedErrorBorder: b(c.danger, 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 14),
            const Text('Add a batch',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
            const SizedBox(height: 4),
            Text('Expired stock is refused by the server.', style: TextStyle(color: c.muted)),
            const SizedBox(height: 16),
            DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              label: const Text('Medicine'),
              dropdownMenuEntries: [
                for (final m in widget.data.medicines)
                  DropdownMenuEntry(value: m.id, label: '${m.name} (${m.productCode})'),
              ],
              onSelected: (id) => setState(() {
                _med = widget.data.medicines.where((m) => m.id == id).firstOrNull;
              }),
            ),
            if (_med != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('Pack of ${_med!.packSize} · lead time ${_med!.leadTimeDays} days',
                    style: TextStyle(color: c.muted, fontSize: 12.5)),
              ),
            const SizedBox(height: 14),
            DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              requestFocusOnTap: false,
              label: const Text('Branch'),
              dropdownMenuEntries: [
                for (final b in widget.data.branches)
                  DropdownMenuEntry(value: b.id, label: b.name),
              ],
              onSelected: (id) => setState(() {
                _branch = widget.data.branches.where((b) => b.id == id).firstOrNull;
              }),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: _dec(c, 'Batch code'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter the batch code.';
                if (t.length > 40) return 'Use 40 characters or fewer.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _qty,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: _dec(c, 'Quantity (units)'),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                return (n == null || n <= 0) ? 'Enter a whole number above zero.' : null;
              },
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Text(_expires == null ? 'Choose expiry date' : 'Expires ${formatDate(_expires!)}'),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.6, color: c.muted),
                    )
                  : const Text('Add batch'),
            ),
          ],
        ),
      ),
    );
  }
}