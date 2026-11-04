import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense_tracker/services/google_sheets_service.dart';

SheetEntry _e(String sms) => SheetEntry(
      transactionId: 'X',
      date: DateTime(2026, 11, 4),
      type: 'Expense',
      description: 'd',
      amount: 1,
      rawSms: sms,
    );

void main() {
  directionTests();
  test('M-Pesa confirmation code at start', () {
    expect(
        _e('TKL3ABC123 Confirmed. Ksh1,500.00 sent to JOHN DOE 0712345678 on 4/11/26 at 10:15 AM.')
            .refNo,
        'TKL3ABC123');
  });
  test('Bank SMS with M-PESA Ref', () {
    expect(
        _e('Dear ANNE, you have received KES 2,000.00 from JANE into ANNE-577715 on 04/11/2026 01.05 PM. M-PESA Ref: TKA1BC2DE3.')
            .refNo,
        'TKA1BC2DE3');
  });
  test('No ref gives empty', () {
    expect(_e('Hello there').refNo, '');
  });
}

SheetEntry _t(String type, String sms) => SheetEntry(
      transactionId: 'X',
      date: DateTime(2026, 11, 4),
      type: type,
      description: 'd',
      amount: 1,
      rawSms: sms,
    );

void directionTests() {
  test('Income goes IN, Expense goes OUT', () {
    expect(_t('Income', '').isIncoming, true);
    expect(_t('Expense', '').isIncoming, false);
  });
  test('Unknown type uses SMS wording', () {
    expect(
        _t('Unknown',
                'Dear ANNE, you have received KES 2,000.00 from JANE into ANNE-577715 on 04/11/2026 01.05 PM.')
            .isIncoming,
        true);
    expect(
        _t('Unknown',
                'TKL3ABC123 Confirmed. Ksh1,500.00 sent to JOHN DOE 0712345678 on 4/11/26 at 10:15 AM.')
            .isIncoming,
        false);
  });
}
