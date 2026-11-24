class CsvException implements Exception {
  const CsvException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CsvTable {
  const CsvTable(this.header, this.rows);

  /// Column names, trimmed and in lower case.
  final List<String> header;
  final List<Map<String, String>> rows;
}

/// A small CSV reader: quotes, commas inside quotes, CRLF, a leading BOM and blank lines.
CsvTable parseCsv(String text) {
  var s = text;
  if (s.startsWith('\uFEFF')) s = s.substring(1);

  final records = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (!(row.length == 1 && row[0].trim().isEmpty)) records.add(row);
    row = <String>[];
  }

  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch == '\r') {
      if (i + 1 < s.length && s[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
    i++;
  }
  if (inQuotes) throw const CsvException('A quoted value is not closed.');
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  if (records.isEmpty) throw const CsvException('The file is empty.');

  final header = [for (final h in records.first) h.trim().toLowerCase()];
  if (header.toSet().length != header.length) {
    throw const CsvException('The header repeats a column name.');
  }

  final rows = <Map<String, String>>[];
  for (final rec in records.skip(1)) {
    if (rec.length != header.length) {
      throw CsvException(
        'Row ${rows.length + 2} has ${rec.length} values but the header has ${header.length}.',
      );
    }
    rows.add({for (var k = 0; k < header.length; k++) header[k]: rec[k].trim()});
  }
  return CsvTable(header, rows);
}