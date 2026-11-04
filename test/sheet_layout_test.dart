import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense_tracker/services/google_sheets_service.dart';

void main() {
  group('findHeaderRow', () {
    test('header in row 1', () {
      expect(
          GoogleSheetsService.findHeaderRow([
            ['Date', 'Description', 'IN', 'OUT', 'Ref No', 'Transaction Id'],
            ['2026-11-04', 'Cement', '', '1500', 'TKL3ABC123', 'X1'],
          ]),
          0);
    });
    test('title rows above the header are skipped', () {
      expect(
          GoogleSheetsService.findHeaderRow([
            ['CONSTRUCTIONS PAYABLES'],
            [],
            ['Date', 'Description', 'IN', 'OUT', 'Ref No', 'Transaction Id'],
          ]),
          2);
    });
    test('no recognisable header', () {
      expect(
          GoogleSheetsService.findHeaderRow([
            ['Foo', 'Bar'],
            ['1', '2'],
          ]),
          -1);
    });
  });

  group('nextFreeRow', () {
    const ours = [0, 1, 2, 3];
    test('empty data -> first row under header', () {
      expect(GoogleSheetsService.nextFreeRow([], ours), 0);
    });
    test('after the last record, skipping blank gaps', () {
      expect(
          GoogleSheetsService.nextFreeRow([
            ['d1', 'a', '', '10'],
            [],
            ['d3', 'c', '5', ''],
          ], ours),
          3);
    });
    test('ignores other columns filled further down (formulas/checkboxes)', () {
      expect(
          GoogleSheetsService.nextFreeRow([
            ['d1', 'a', '', '10', '', 'FALSE'],
            ['', '', '', '', '', 'FALSE'],
            ['', '', '', '', '', 'FALSE'],
          ], ours),
          1);
    });
  });
}
