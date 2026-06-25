import '../models/rent_payment.dart';

/// Extracts a [RentPayment] from any Kenyan transaction SMS — money **received**
/// or **sent** (M-Pesa direct, bank alerts, LOOP/overdraft, paybill, etc.).
///
/// It is intentionally lenient: the business keyword decides *which* SMS belong
/// to a ledger; this just pulls out whatever fields are present (amount, party,
/// refs, date/time). The only hard requirement is a currency amount.
///
/// Examples handled:
///   Dear ANNE …, you have received KES 10850.00 into ANNE-577715 from SHARON
///   CHEPTOO 254708822168 Ref: S2007 Mpesa Ref:UFCA581QLT on 12/06/26 at 01.05 PM. DTB
///
///   You have successfully sent KES.2,300.00 to PETER SHOP-4983166. LOOP Ref
///   NHE59Y82G5EF M-Pesa Ref UFPU914MEK on 25/06/2026 15:00:54.
class RentSmsParser {
  // A currency amount: KES/KSH/Ksh, optional dot/space, then the number.
  static final RegExp _amount = RegExp(
      r'(?:KES|KSH|KSh|Ksh)\s*\.?\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false);

  static final RegExp _noise = RegExp(
      r'\b(otp|one[- ]?time (?:password|pin)|verification code|verify your)\b',
      caseSensitive: false);

  static final RegExp _received =
      RegExp(r'\b(received|credited|deposited)\b', caseSensitive: false);

  // "from NAME ..." / "to NAME ..." up to a delimiter or a keyword boundary.
  static final RegExp _fromName = RegExp(
      r'from\s+(.+?)(?=[.,]|\s+(?:on|loop|m-?pesa|ref|new|via|fee|account)\b|$)',
      caseSensitive: false);
  static final RegExp _toName = RegExp(
      r'to\s+(.+?)(?=[.,]|\s+(?:on|loop|m-?pesa|ref|new|via|fee|account)\b|$)',
      caseSensitive: false);

  static final RegExp _phone = RegExp(r'(?:254|0)\d{8,9}');
  static final RegExp _trailingPhone = RegExp(r'\s*(?:254|0)\d{8,9}\s*$');

  static final RegExp _mpesaRef =
      RegExp(r'M-?PESA\s*Ref[:.,]?\s*([A-Z0-9]{8,14})', caseSensitive: false);
  static final RegExp _loopRef =
      RegExp(r'LOOP\s*Ref[:.,]?\s*([A-Z0-9]{8,14})', caseSensitive: false);
  static final RegExp _genericRef = RegExp(
      r'(?<![A-Za-z])Ref[:.,]?\s*([A-Za-z0-9]{4,14})',
      caseSensitive: false);

  // "into ANNE-577715" (received destination)
  static final RegExp _account = RegExp(r'into\s+(\S+)', caseSensitive: false);
  static final RegExp _holder = RegExp(r'Dear\s+(.+?)\s*,', caseSensitive: false);

  static final RegExp _date = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{2,4})');
  // 12-hour with meridiem, e.g. "01.05 PM"
  static final RegExp _time12 =
      RegExp(r'\b(\d{1,2})[.:](\d{2})\s*(AM|PM)\b', caseSensitive: false);
  // 24-hour with a colon, e.g. "15:00:54"
  static final RegExp _time24 = RegExp(r'\b(\d{1,2}):(\d{2})(?::\d{2})?\b');

  static bool matches(String body) => parse(body) != null;

  /// Returns a [RentPayment] if [body] is a transaction SMS (has an amount),
  /// else null.
  static RentPayment? parse(String body, {DateTime? smsDate}) {
    if (body.isEmpty) return null;
    if (_noise.hasMatch(body)) return null;

    final amountMatch = _amount.firstMatch(body);
    if (amountMatch == null) return null;
    final amount =
        double.tryParse(amountMatch.group(1)!.replaceAll(',', '')) ?? 0;
    if (amount <= 0) return null;

    final isReceived = _received.hasMatch(body);

    // Party: from <name> for incoming, to <name> for outgoing.
    String name = (isReceived
            ? _fromName.firstMatch(body)?.group(1)
            : _toName.firstMatch(body)?.group(1) ??
                _fromName.firstMatch(body)?.group(1)) ??
        '';
    name = name.replaceAll(_trailingPhone, '').trim();

    final mpesaRef = _mpesaRef.firstMatch(body)?.group(1)?.trim() ?? '';
    final loop = _loopRef.firstMatch(body)?.group(1)?.trim() ?? '';
    final ref = loop.isNotEmpty
        ? loop
        : (_genericRef.firstMatch(body)?.group(1)?.trim() ?? '');

    final paidAt = _composeDateTime(body) ?? smsDate ?? DateTime.now();

    return RentPayment(
      holder: _holder.firstMatch(body)?.group(1)?.trim() ?? '',
      tenantName: name,
      phone: _phone.firstMatch(body)?.group(0) ?? '',
      amount: amount,
      paidIntoAccount: _account.firstMatch(body)?.group(1)?.trim() ?? '',
      ref: ref,
      mpesaRef: mpesaRef,
      bank: isReceived ? 'In' : 'Out',
      paidAt: paidAt,
      rawSms: body.trim(),
    );
  }

  static DateTime? _composeDateTime(String body) {
    final d = _date.firstMatch(body);
    if (d == null) return null;
    final day = int.parse(d.group(1)!);
    final month = int.parse(d.group(2)!);
    var year = int.parse(d.group(3)!);
    if (year < 100) year += 2000;

    var hour = 0;
    var minute = 0;
    final t12 = _time12.firstMatch(body);
    if (t12 != null) {
      hour = int.parse(t12.group(1)!);
      minute = int.parse(t12.group(2)!);
      final mer = t12.group(3)!.toUpperCase();
      if (mer == 'PM' && hour != 12) hour += 12;
      if (mer == 'AM' && hour == 12) hour = 0;
    } else {
      final t24 = _time24.firstMatch(body);
      if (t24 != null) {
        hour = int.parse(t24.group(1)!);
        minute = int.parse(t24.group(2)!);
      }
    }
    return DateTime(year, month, day, hour, minute);
  }
}
