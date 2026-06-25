import 'package:flutter_test/flutter_test.dart';
import 'package:smart_expense_tracker/services/rent_sms_parser.dart';

void main() {
  group('RentSmsParser (universal transaction parser)', () {
    test('parses a received DTB/bank payment', () {
      final p = RentSmsParser.parse(
        'Dear ANNE CHERONO CHUMO, you have received KES 10850.00 into ANNE-577715 '
        'from SHARON CHEPTOO  254708822168 Ref: S2007 Mpesa Ref:UFCA581QLT '
        'on 12/06/26 at 01.05 PM. DTB',
      );
      expect(p, isNotNull);
      expect(p!.amount, 10850.00);
      expect(p.tenantName, 'SHARON CHEPTOO');
      expect(p.phone, '254708822168');
      expect(p.ref, 'S2007');
      expect(p.mpesaRef, 'UFCA581QLT');
      expect(p.bank, 'In'); // received
      expect(p.paidAt, DateTime(2026, 6, 12, 13, 5));
    });

    test('parses a direct M-Pesa received payment', () {
      final p = RentSmsParser.parse(
        'UFCA581QLT Confirmed. You have received Ksh10,850.00 from SHARON CHEPTOO '
        '254708822168 on 12/6/26 at 1.05 PM. New M-PESA balance is Ksh20,000.00.',
      );
      expect(p, isNotNull);
      expect(p!.amount, 10850.00);
      expect(p.tenantName, 'SHARON CHEPTOO');
      expect(p.bank, 'In');
    });

    test('parses an OUTGOING LOOP "sent" payment (the case that was failing)', () {
      final p = RentSmsParser.parse(
        'You have successfully sent KES.2,300.00 to PETER SHOP-4983166. '
        'LOOP Ref NHE59Y82G5EF M-Pesa Ref UFPU914MEK on 25/06/2026 15:00:54.',
      );
      expect(p, isNotNull);
      expect(p!.amount, 2300.00);
      expect(p.tenantName, 'PETER SHOP-4983166');
      expect(p.ref, 'NHE59Y82G5EF'); // LOOP ref
      expect(p.mpesaRef, 'UFPU914MEK');
      expect(p.bank, 'Out'); // sent
      expect(p.paidAt, DateTime(2026, 6, 25, 15, 0));
    });

    test('parses an outgoing paybill payment', () {
      final p = RentSmsParser.parse(
        'M-PESA Paybill Successful:KES.7,910.00 to 516600 - DTB Account -546647 '
        'LOOP Ref NHE59Y8TV3ZI, M-Pesa Ref UFPU914JGY, Fee: KES.57.50 '
        'on 25/06/2026 14:40:54.',
      );
      expect(p, isNotNull);
      expect(p!.amount, 7910.00); // first amount, not the fee
      expect(p.bank, 'Out');
      expect(p.ref, 'NHE59Y8TV3ZI');
    });

    test('rejects OTP / empty messages', () {
      expect(RentSmsParser.parse('Your OTP is 123456'), isNull);
      expect(RentSmsParser.parse('Use verification code 8842 to verify your number'),
          isNull);
      expect(RentSmsParser.parse(''), isNull);
    });
  });
}
