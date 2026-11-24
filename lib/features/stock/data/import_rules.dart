import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/utils/csv_parser.dart';

class ImportRules {
  const ImportRules._();

  static const int maxBytes = 1048576; // 1 MB
  static const int maxRows = 5000;
  static const List<String> required = ['date', 'branch', 'product_code', 'quantity'];
  static const Set<String> allowed = {'date', 'branch', 'product_code', 'quantity', 'flag'};
}

class ImportProblem implements Exception {
  const ImportProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

class PreparedImport {
  const PreparedImport({required this.fileName, required this.rows, required this.hash});

  final String fileName;
  final List<Map<String, String>> rows;

  /// SHA-256 of the file. The server uses it to spot a repeated upload.
  final String hash;
}

String _decode(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw const ImportProblem('The file is not plain UTF-8 text.');
  }
}

CsvTable _parse(String text) {
  try {
    return parseCsv(text);
  } on CsvException catch (e) {
    throw ImportProblem(e.message);
  }
}

/// Quick checks on the phone before anything is sent. The server checks again.
PreparedImport prepareImport({required String fileName, required Uint8List bytes}) {
  if (!fileName.toLowerCase().endsWith('.csv')) {
    throw const ImportProblem('Only .csv files are accepted.');
  }
  if (bytes.length > ImportRules.maxBytes) {
    throw const ImportProblem('The file is larger than 1 MB.');
  }
  final table = _parse(_decode(bytes));

  final missing = [
    for (final c in ImportRules.required)
      if (!table.header.contains(c)) c,
  ];
  if (missing.isNotEmpty) {
    throw ImportProblem('Missing columns: ${missing.join(', ')}.');
  }
  final extra = [
    for (final c in table.header)
      if (!ImportRules.allowed.contains(c)) c,
  ];
  if (extra.isNotEmpty) {
    throw ImportProblem(
      'These columns are not allowed: ${extra.join(', ')}. Remove personal or unknown fields and try again.',
    );
  }
  if (table.rows.isEmpty) throw const ImportProblem('The file has no data rows.');
  if (table.rows.length > ImportRules.maxRows) {
    throw const ImportProblem('The file has more than 5,000 rows.');
  }
  return PreparedImport(
    fileName: fileName,
    rows: table.rows,
    hash: sha256.convert(bytes).toString(),
  );
}