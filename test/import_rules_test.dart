import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/features/stock/data/import_rules.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  const good = 'date,branch,product_code,quantity\n2026-11-20,Uttara,NAPA500,20\n';

  test('a good file is accepted and its hash is stable', () {
    final a = prepareImport(fileName: 'sales.csv', bytes: _bytes(good));
    final b = prepareImport(fileName: 'other-name.csv', bytes: _bytes(good));
    expect(a.rows.single['product_code'], 'NAPA500');
    expect(a.hash, b.hash);
    expect(a.hash.length, 64);
  });

  test('only .csv files are accepted', () {
    expect(
      () => prepareImport(fileName: 'sales.xlsx', bytes: _bytes(good)),
      throwsA(isA<ImportProblem>()),
    );
  });

  test('personal columns reject the file', () {
    const bad = 'date,branch,product_code,quantity,patient_name\n2026-11-20,Uttara,NAPA500,20,X\n';
    expect(
      () => prepareImport(fileName: 'sales.csv', bytes: _bytes(bad)),
      throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('patient_name'))),
    );
  });

  test('missing required columns are named', () {
    expect(
      () => prepareImport(fileName: 'sales.csv', bytes: _bytes('date,branch\n2026-11-20,Uttara\n')),
      throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('product_code'))),
    );
  });

  test('a file over 1 MB is refused', () {
    final big = Uint8List(ImportRules.maxBytes + 1);
    expect(
      () => prepareImport(fileName: 'sales.csv', bytes: big),
      throwsA(isA<ImportProblem>()),
    );
  });
}