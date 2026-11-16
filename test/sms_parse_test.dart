import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense_tracker/services/sms_service.dart';

void main() {
  final date = DateTime(2026, 10, 29, 12);
  final keywords = SmsService.defaultKeywords;
  Transaction? parse(String body, [List<String>? kw]) =>
      SmsService.parseSms(body, date, 'SMS_MPESA_1', kw ?? keywords);

  group('real transactions are kept', () {
    test('word containing "pin" (SHOPPING)', () {
      final t = parse('UJT4AB12CD Confirmed. Ksh1,250.00 paid to KAPSOWAR '
          'SHOPPING CENTRE. on 29/10/26 at 1:05 PM.');
      expect(t?.amount, 1250);
      expect(t?.type, 'Expense');
    });

    test('word containing "otp" (HOTPOINT)', () {
      expect(
          parse('UJT4AB12CD Confirmed. Ksh900.00 sent to HOTPOINT APPLIANCES '
                  'on 29/10/26.')
              ?.amount,
          900);
    });

    test('alert with a "never share your PIN" footer', () {
      expect(
          parse('You have received KES 5,000.00 into ACC-1 from JANE. '
                  'Never share your PIN or OTP.')
              ?.amount,
          5000);
    });

    test('amounts under Ksh 10', () {
      expect(
          parse('UJT4AB12CD Confirmed. Ksh5.00 sent to JOHN on 29/10/26.')
              ?.amount,
          5);
    });

    test('refunds and reversals', () {
      final refund = parse('Refund of KES 700.00 has been credited to you.');
      expect(refund?.amount, 700);
      expect(refund?.type, 'Income');
      expect(
          parse('UJT4AB12CD Confirmed. Reversal of transaction UJS1XY98ZZ. '
                  'Ksh300.00 is credited to your M-PESA account.')
              ?.amount,
          300);
    });

    test('LOOP format with a dot after KES', () {
      final t = parse('You have successfully sent KES.2,300.00 to PETER '
          'SHOP-4983166. LOOP Ref NHE59Y82G5EF M-Pesa Ref UFPU914MEK on '
          '25/06/2026 15:00:54.');
      expect(t?.amount, 2300);
      expect(t?.transactionId, 'NHE59Y82G5EF');
    });

    test('code ending in ID + digit is not read as the amount', () {
      expect(
          parse('UJT4AB1ID7 Confirmed. Ksh1,000.00 sent to JOHN on 29/10/26.')
              ?.amount,
          1000);
    });

    test('a saved keyword beyond the defaults still matches', () {
      const body = 'Rent 15000 for block A';
      expect(parse(body, ['rent'])?.amount, 15000);
      expect(parse(body, ['water']), isNull);
    });
  });

  group('non-transactions are still excluded', () {
    test('OTP', () {
      expect(parse('Your OTP is 482913. It expires in 5 minutes.'), isNull);
      expect(parse('Your OTP for KES 500 payment is 4829.'), isNull);
    });

    test('PIN and password notices', () {
      expect(parse('Your M-PESA PIN was changed on account 1234.'), isNull);
      expect(parse('Your password code is 998877.'), isNull);
    });
  });

  group('transaction id', () {
    test('plain words never become a shared id', () {
      const a = 'Transaction completed. KES 100.00 paid to A.';
      const b = 'Transaction completed. KES 250.00 paid to B.';
      expect(parse(a)?.transactionId, 'SMS_MPESA_1');
      expect(parse(b)?.transactionId, 'SMS_MPESA_1'); // Unique per message.
      expect(parse('Transaction Reference: KES 100.00 paid')?.transactionId,
          'SMS_MPESA_1');
    });
  });
}
