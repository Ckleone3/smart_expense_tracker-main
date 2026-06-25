import 'package:hive/hive.dart';

/// A single rent payment parsed from a bank/M-Pesa "received" SMS.
///
/// This is the row that replaces a line in the landlord's manual book and
/// becomes a row in the exported CSV report.
class RentPayment {
  /// Account holder / recipient named in the SMS (the landlord), e.g. "ANNE CHERONO CHUMO".
  final String holder;

  /// The payer / tenant, e.g. "SHARON CHEPTOO".
  final String tenantName;

  /// Payer phone number, e.g. "254708822168".
  final String phone;

  /// Amount received.
  final double amount;

  /// Account the money was paid into, e.g. "ANNE-577715".
  final String paidIntoAccount;

  /// Bank/sender reference, e.g. "S2007".
  final String ref;

  /// M-Pesa transaction reference, e.g. "UFCA581QLT". Used for de-duplication.
  final String mpesaRef;

  /// Channel/bank tag, e.g. "DTB".
  final String bank;

  /// When the payment was made (parsed from the SMS date/time).
  final DateTime paidAt;

  /// Original SMS text, kept for audit.
  final String rawSms;

  RentPayment({
    required this.holder,
    required this.tenantName,
    required this.phone,
    required this.amount,
    required this.paidIntoAccount,
    required this.ref,
    required this.mpesaRef,
    required this.bank,
    required this.paidAt,
    required this.rawSms,
  });

  /// Stable key for de-duplication and as the Hive box key.
  /// Prefers the unique M-Pesa ref, then any other ref, then time+amount.
  String get dedupeKey => mpesaRef.isNotEmpty
      ? mpesaRef
      : ref.isNotEmpty
          ? 'ref_$ref'
          : '${paidAt.millisecondsSinceEpoch}_${amount.toStringAsFixed(2)}';

  Map<String, dynamic> toJson() => {
        'holder': holder,
        'tenantName': tenantName,
        'phone': phone,
        'amount': amount,
        'paidIntoAccount': paidIntoAccount,
        'ref': ref,
        'mpesaRef': mpesaRef,
        'bank': bank,
        'paidAt': paidAt.toIso8601String(),
        'rawSms': rawSms,
      };

  /// Builds a [RentPayment] from a JSON map. Tolerant of the slightly
  /// different shapes that the native receiver may send over the MethodChannel
  /// (e.g. amount as String, paidAt as epoch millis).
  factory RentPayment.fromJson(Map<dynamic, dynamic> json) {
    double parseAmount(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString().replaceAll(',', '') ?? '') ?? 0;
    }

    DateTime parseDate(dynamic v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    }

    return RentPayment(
      holder: (json['holder'] ?? '').toString(),
      tenantName: (json['tenantName'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      amount: parseAmount(json['amount']),
      paidIntoAccount: (json['paidIntoAccount'] ?? '').toString(),
      ref: (json['ref'] ?? '').toString(),
      mpesaRef: (json['mpesaRef'] ?? '').toString(),
      bank: (json['bank'] ?? '').toString(),
      paidAt: parseDate(json['paidAt']),
      rawSms: (json['rawSms'] ?? '').toString(),
    );
  }
}

/// Hand-written Hive adapter (typeId 10 — 0 is already used by Expense/Transaction).
/// Hand-written to avoid running build_runner.
class RentPaymentAdapter extends TypeAdapter<RentPayment> {
  @override
  final int typeId = 10;

  @override
  RentPayment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RentPayment(
      holder: fields[0] as String,
      tenantName: fields[1] as String,
      phone: fields[2] as String,
      amount: fields[3] as double,
      paidIntoAccount: fields[4] as String,
      ref: fields[5] as String,
      mpesaRef: fields[6] as String,
      bank: fields[7] as String,
      paidAt: DateTime.parse(fields[8] as String),
      rawSms: fields[9] as String,
    );
  }

  @override
  void write(BinaryWriter writer, RentPayment obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.holder)
      ..writeByte(1)
      ..write(obj.tenantName)
      ..writeByte(2)
      ..write(obj.phone)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.paidIntoAccount)
      ..writeByte(5)
      ..write(obj.ref)
      ..writeByte(6)
      ..write(obj.mpesaRef)
      ..writeByte(7)
      ..write(obj.bank)
      ..writeByte(8)
      ..write(obj.paidAt.toIso8601String())
      ..writeByte(9)
      ..write(obj.rawSms);
  }
}
