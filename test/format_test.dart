import 'package:flutter_test/flutter_test.dart';
import 'package:medivo/core/utils/format.dart';

void main() {
  test('long hashes are shortened', () {
    expect(shortHash('abcdef1234567890abcdef'), 'abcdef…cdef');
    expect(shortHash('short'), 'short');
  });

  test('durations read naturally', () {
    expect(humanDuration(const Duration(minutes: 5)), '5 min');
    expect(humanDuration(const Duration(seconds: 60)), '1 min');
    expect(humanDuration(const Duration(seconds: 20)), '20 sec');
  });

  test('action names become sentences', () {
    expect(sentenceCase('batch added'), 'Batch added');
    expect(sentenceCase('add_batch denied'), 'Add batch denied');
    expect(sentenceCase(''), '');
  });
}