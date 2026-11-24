import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/utils/csv_parser.dart';

void main() {
  test('reads a header and rows, trimmed and lower case', () {
    final t = parseCsv(' Date , Branch \n2026-11-20, Uttara \n');
    expect(t.header, ['date', 'branch']);
    expect(t.rows.single, {'date': '2026-11-20', 'branch': 'Uttara'});
  });

  test('handles quotes, commas inside quotes and escaped quotes', () {
    final t = parseCsv('a,b\n"x, y","say ""hi"""\n');
    expect(t.rows.single, {'a': 'x, y', 'b': 'say "hi"'});
  });

  test('handles CRLF, a leading BOM and blank lines', () {
    final t = parseCsv('\uFEFFa,b\r\n1,2\r\n\r\n3,4\r\n');
    expect(t.rows.length, 2);
    expect(t.rows.last, {'a': '3', 'b': '4'});
  });

  test('a row with the wrong number of values names the row', () {
    expect(
      () => parseCsv('a,b\n1,2\n3\n'),
      throwsA(isA<CsvException>().having((e) => e.message, 'message', contains('Row 3'))),
    );
  });

  test('an unclosed quote is an error', () {
    expect(() => parseCsv('a,b\n"x,2\n'), throwsA(isA<CsvException>()));
  });

  test('a repeated column name is an error', () {
    expect(() => parseCsv('a,a\n1,2\n'), throwsA(isA<CsvException>()));
  });
}