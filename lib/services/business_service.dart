import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/business.dart';
import '../models/rent_payment.dart';
import 'rent_sms_parser.dart';
import 'sms_service.dart' show Transaction;

/// A keyword candidate discovered in the SMS history (a payment destination /
/// reference token), offered when setting up a business.
class KeywordSuggestion {
  final String keyword;
  final int payments;
  final int payers;
  KeywordSuggestion(
      {required this.keyword, required this.payments, required this.payers});
}

/// Owns the list of businesses/ledgers and the keyword matching that decides
/// which payments belong to which business.
class BusinessService {
  static const _channel = MethodChannel('rent_capture');
  static const _boxName = 'businesses';

  Box<Business>? _box;

  Future<Box<Business>> _open() async {
    if (_box != null && _box!.isOpen) return _box!;
    if (!Hive.isAdapterRegistered(12)) {
      Hive.registerAdapter(BusinessAdapter());
    }
    _box = await Hive.openBox<Business>(_boxName);
    await _migrateFromRentConfig();
    return _box!;
  }

  /// Carry over the old single rent-account setup into a first business so
  /// existing users don't lose their configuration.
  Future<void> _migrateFromRentConfig() async {
    if (_box!.isNotEmpty) return;
    try {
      final cfg = await Hive.openBox('rent_config');
      final keywords =
          (cfg.get('rent_accounts_display') as List?)?.cast<String>() ??
              const <String>[];
      final name = (cfg.get('business_name') as String?)?.trim() ?? '';
      if (keywords.isNotEmpty || name.isNotEmpty) {
        final b = Business(
          id: newId(),
          name: name.isEmpty ? 'My Business' : name,
          keywords: keywords,
        );
        await _box!.put(b.id, b);
        log('Migrated rent config into business "${b.name}"');
      }
    } catch (e) {
      log('Rent-config migration skipped: $e');
    }
  }

  String newId() => 'b_${DateTime.now().microsecondsSinceEpoch}';

  Future<List<Business>> all() async {
    final box = await _open();
    final list = box.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<bool> get hasBusinesses async => (await _open()).isNotEmpty;

  Future<void> save(Business b) async {
    final box = await _open();
    await box.put(b.id, b);
    await pushKeywordsToNative();
    log('Saved business "${b.name}" with ${b.keywords.length} keyword(s)');
  }

  Future<void> delete(String id) async {
    final box = await _open();
    await box.delete(id);
    await pushKeywordsToNative();
  }

  /// Every keyword key across all businesses (for capture + native matchers).
  Future<Set<String>> allKeywordKeys() async {
    final box = await _open();
    return box.values.expand((b) => b.keywordKeys).toSet();
  }

  /// Does this payment belong to [b]? True if the SMS contains any of the
  /// business's keywords.
  bool matches(Business b, RentPayment p) {
    final body = Business.normalize(p.rawSms);
    return b.keywordKeys.any((k) => body.contains(k));
  }

  bool matchesAnyKey(Set<String> keys, RentPayment p) {
    final body = Business.normalize(p.rawSms);
    return keys.any((k) => body.contains(k));
  }

  /// Mirror the keyword set to the native receiver so closed-app capture only
  /// fires for configured businesses.
  Future<void> pushKeywordsToNative() async {
    final keys = await allKeywordKeys();
    try {
      await _channel.invokeMethod('setLedgerKeywords', {'keywords': keys.toList()});
    } on PlatformException catch (e) {
      log('Failed to push ledger keywords to native: $e');
    }
  }

  /// Scans SMS history for likely keywords (payment destinations/refs) the user
  /// could attach to a business, most common first.
  Future<List<KeywordSuggestion>> suggestKeywords(
      Box<Transaction> transactionBox) async {
    final existing = await allKeywordKeys();
    final payments = <String, int>{};
    final payers = <String, Set<String>>{};
    final display = <String, String>{};

    for (final t in transactionBox.values) {
      final p = RentSmsParser.parse(t.rawSms, smsDate: DateTime.tryParse(t.date));
      if (p == null) continue;
      final token = p.paidIntoAccount.isNotEmpty ? p.paidIntoAccount : p.ref;
      if (token.isEmpty) continue;
      final key = Business.normalize(token);
      if (key.isEmpty || existing.contains(key)) continue;
      display.putIfAbsent(key, () => token);
      payments[key] = (payments[key] ?? 0) + 1;
      (payers[key] ??= <String>{}).add(
          p.phone.isNotEmpty ? p.phone : p.tenantName.toLowerCase());
    }

    final out = display.keys
        .map((k) => KeywordSuggestion(
              keyword: display[k]!,
              payments: payments[k] ?? 0,
              payers: payers[k]?.length ?? 0,
            ))
        .toList()
      ..sort((a, b) => b.payers.compareTo(a.payers));
    return out;
  }
}
