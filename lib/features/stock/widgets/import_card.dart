import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/medivo_card.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/import_rules.dart';
import '../data/stock_models.dart';
import '../stock_controller.dart';
import 'stock_style.dart';

class ImportCard extends ConsumerStatefulWidget {
  const ImportCard({super.key, required this.canImport});

  final bool canImport;

  @override
  ConsumerState<ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends ConsumerState<ImportCard> {
  bool _busy = false;
  String? _error;
  PreparedImport? _prepared;
  ImportSummary? _summary;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _summary = null;
      _prepared = null;
    });
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
    } catch (_) {
      setState(() => _error = 'Could not open the file picker.');
      return;
    }
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    final bytes = f.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the file.');
      return;
    }
    try {
      final p = prepareImport(fileName: f.name, bytes: bytes);
      setState(() => _prepared = p);
    } on ImportProblem catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _upload() async {
    final p = _prepared;
    if (p == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(stockRepositoryProvider)
          .importSales(rows: p.rows, fileHash: p.hash);
      if (!mounted) return;
      refreshAfterChange(ref);
      setState(() {
        _busy = false;
        _summary = ImportSummary.fromResult(r);
        if (r.ok || (_summary?.errors.isNotEmpty ?? false)) _prepared = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reach the server. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final s = _summary;

    return MedivoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Import sales',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'CSV with the columns date, branch, product_code, quantity (and optional flag). '
            'Files with personal columns are rejected. Limits: 1 MB, 5,000 rows.',
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (!widget.canImport)
            Row(
              children: [
                Icon(Icons.lock_rounded, color: c.muted, size: 20),
                const SizedBox(width: 10),
                const Expanded(child: Text('Your role cannot import sales.')),
              ],
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Choose a CSV file'),
            ),
            if (_prepared != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.description_rounded, color: c.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${_prepared!.fileName} · ${_prepared!.rows.length} rows ready',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _upload,
                child: _busy
                    ? SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: c.muted),
                      )
                    : Text('Import ${_prepared!.rows.length} rows'),
              ),
            ],
          ],
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
          if (s != null) ...[
            const SizedBox(height: 12),
            if (s.duplicate)
              Row(
                children: [
                  StatusChip(label: 'Already imported', color: c.secondary),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Same file, nothing was added again.')),
                ],
              )
            else ...[
              if (s.message != null) ErrorBanner(s.message!),
              if (s.ok)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusChip(label: '${s.accepted} rows accepted', color: c.primary),
                    if (s.rejected > 0)
                      StatusChip(label: '${s.rejected} rejected', color: c.warning),
                  ],
                ),
              for (final e in s.errors.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Row ${e.row}: ${e.message}',
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                ),
              if (s.errors.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('…and ${s.errors.length - 5} more.',
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                ),
            ],
          ],
        ],
      ),
    );
  }
}