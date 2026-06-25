import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../models/business.dart';
import '../models/rent_payment.dart';
import 'business_service.dart';
import 'rent_sms_parser.dart';
import 'sms_service.dart' show Transaction;

/// Captures "money received" SMS into a local ledger and produces a per-business
/// CSV. A payment belongs to a business when the SMS contains one of that
/// business's keywords (see [BusinessService]).
class LedgerService {
  static const _channel = MethodChannel('rent_capture');
  static const _boxName = 'rent_payments'; // existing capture box (reused)
  static const _ignoredBoxName = 'rent_ignored';

  final BusinessService businesses;

  LedgerService({BusinessService? businesses})
      : businesses = businesses ?? BusinessService();

  Box<RentPayment>? _box;
  Box? _ignored;

  Future<Box<RentPayment>> _open() async {
    if (_box != null && _box!.isOpen) return _box!;
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(RentPaymentAdapter());
    }
    _box = await Hive.openBox<RentPayment>(_boxName);
    _ignored = await Hive.openBox(_ignoredBoxName);
    return _box!;
  }

  bool _isIgnored(String key) => _ignored?.containsKey(key) ?? false;

  /// Removes a captured payment and remembers it so it is never re-added
  /// (for a wrongly-matched SMS).
  Future<void> delete(RentPayment payment) async {
    final box = await _open();
    await _ignored!.put(payment.dedupeKey, true);
    await box.delete(payment.dedupeKey);
  }

  /// Drains records captured natively while the app was closed, keeping any
  /// that match a configured business keyword.
  Future<int> syncFromNative() async {
    final box = await _open();
    final keys = await businesses.allKeywordKeys();
    int added = 0;
    try {
      final raw = await _channel.invokeMethod<String>('getAndClearPending');
      if (raw == null || raw.isEmpty) return 0;
      final list = jsonDecode(raw);
      if (list is! List) return 0;
      for (final item in list) {
        if (item is Map) {
          final p = RentPayment.fromJson(item);
          if (_isIgnored(p.dedupeKey) || box.containsKey(p.dedupeKey)) continue;
          if (!businesses.matchesAnyKey(keys, p)) continue;
          await box.put(p.dedupeKey, p);
          added++;
        }
      }
    } on PlatformException catch (e) {
      log('Native ledger sync failed: $e');
    } catch (e) {
      log('Ledger sync parse error: $e');
    }
    return added;
  }

  /// Scans already-stored SMS and adds payments matching any business keyword.
  Future<int> backfillFromTransactions(Box<Transaction> transactionBox) async {
    final box = await _open();
    final keys = await businesses.allKeywordKeys();
    if (keys.isEmpty) return 0;
    int added = 0;
    for (final t in transactionBox.values) {
      if (t.rawSms.isEmpty) continue;
      final p = RentSmsParser.parse(t.rawSms, smsDate: DateTime.tryParse(t.date));
      if (p == null) continue;
      if (_isIgnored(p.dedupeKey) || box.containsKey(p.dedupeKey)) continue;
      if (!businesses.matchesAnyKey(keys, p)) continue;
      await box.put(p.dedupeKey, p);
      added++;
    }
    return added;
  }

  /// Payments for one [business] within [start]..[end], newest first.
  Future<List<RentPayment>> query(Business business,
      {DateTime? start, DateTime? end}) async {
    final box = await _open();
    final items = box.values.where((p) {
      if (start != null && p.paidAt.isBefore(start)) return false;
      if (end != null && p.paidAt.isAfter(end)) return false;
      return businesses.matches(business, p);
    }).toList()
      ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return items;
  }

  double total(List<RentPayment> items) =>
      items.fold(0.0, (sum, p) => sum + p.amount);

  static const csvHeaders = <String>[
    'Date', 'Time', 'Type', 'Name', 'Phone', 'Amount (KES)', 'Paid To',
    'Reference', 'M-Pesa Code',
  ];

  List<String> csvRowFor(RentPayment p) => <String>[
        DateFormat('yyyy-MM-dd').format(p.paidAt),
        DateFormat('hh:mm a').format(p.paidAt),
        p.bank, // 'In' or 'Out'
        p.tenantName,
        p.phone,
        p.amount.toStringAsFixed(2),
        p.paidIntoAccount,
        p.ref,
        p.mpesaRef,
      ];

  List<String> totalRow(List<RentPayment> items) =>
      ['', '', '', '', 'TOTAL', total(items).toStringAsFixed(2)];

  List<List<String>> buildCsvMatrix(List<RentPayment> items) =>
      [csvHeaders, ...items.map(csvRowFor), totalRow(items)];

  /// Writes the CSV (titled with the business name + range) and opens the share
  /// sheet. Returns the file path.
  Future<String> exportCsv(Business business, List<RentPayment> items,
      {String? rangeLabel}) async {
    final out = <List<String>>[
      [business.name],
      if (rangeLabel != null) [rangeLabel],
      <String>[],
      ...buildCsvMatrix(items),
    ];
    final csv = const ListToCsvConverter().convert(out);
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final safe = business.name.isEmpty
        ? 'ledger'
        : business.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toLowerCase();
    final file = File('${dir.path}/${safe}_$stamp.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: business.name.isEmpty ? 'Ledger report' : business.name,
    );
    return file.path;
  }

  /// Requests POST_NOTIFICATIONS (Android 13+) so capture alerts can show.
  Future<void> ensureNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }
}
