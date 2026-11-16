// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:developer';
import 'dart:convert'; // For MD5 hashing
import 'package:crypto/crypto.dart'; // For MD5 hashing
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart' as smsInbox;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart'; // for trial
import 'package:smart_expense_tracker/services/subscription_service.dart';

part 'sms_service.g.dart';

@HiveType(typeId: 1)
class Transaction extends HiveObject {
  @HiveField(0)
  final String type;

  @HiveField(1)
  final double amount;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final String date;

  @HiveField(4)
  final String transactionId;

  @HiveField(5)
  final String rawSms;

  @HiveField(6)
  final String? categoryId; // Added to track categorization

  Transaction({
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
    required this.transactionId,
    required this.rawSms,
    this.categoryId, // Optional, null means uncategorized
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'amount': amount,
      'description': description,
      'date': date,
      'transactionId': transactionId,
      'rawSms': rawSms,
      'categoryId': categoryId,
    };
  }

  // Create a copy with updated categoryId
  Transaction withCategoryId(String? newCategoryId) {
    return Transaction(
      type: type,
      amount: amount,
      description: description,
      date: date,
      transactionId: transactionId,
      rawSms: rawSms,
      categoryId: newCategoryId,
    );
  }
}

class _ParsedSms {
  final Transaction tx;

  /// Id of the message in the local store, unique to this SMS.
  final String storedId;

  _ParsedSms(this.tx, this.storedId);
}

class SmsService {
  final smsInbox.SmsQuery _smsQuery = smsInbox.SmsQuery();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SubscriptionService _subscriptionService;
  List<String> _cachedKeywords = [];
  bool _keywordsLoaded = false;
  late Box<Transaction> _transactionBox;
  Timer? _pollingTimer;
  bool _isInitialized = false;
  bool _isRequestingPermissions =
      false; // Flag to prevent concurrent permission requests

  static const List<String> _defaultKeywords = [
    'received',
    'credited',
    'deposit',
    'added',
    'salary',
    'payment',
    'refund',
    'sent',
    'paid',
    'debited',
    'withdrawn',
    'transfer',
    'purchase',
    'charged',
    'transaction',
    'balance',
    'account',
    'success',
    'completed',
    'ref',
    'reference',
    'code',
    'id',
    'amount',
    'ksh',
    'kes'
  ];

  static const String _transactionBoxName = 'transactions';
  static const String _lastSyncKey = 'lastSyncTimestamp';
  static const int _batchSize = 500;
  static const String _backfillKey = 'sms_backfill_v2_done';

  /// A later sync re-reads this far back, so a message that reached the inbox
  /// late (or after another sync) is still picked up.
  static const Duration _syncOverlap = Duration(days: 2);

  static List<String> get defaultKeywords => _defaultKeywords;

  // ① Expose the box so other widgets/services can read directly:
  Box<Transaction> get transactionBox => _transactionBox;

  SmsService({SubscriptionService? subscriptionService})
      : _subscriptionService = subscriptionService ?? SubscriptionService() {
    _loadKeywords();
  }

  Future<void> init() async {
    if (_isInitialized) return;
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TransactionAdapter());
    }
    try {
      _transactionBox = await Hive.openBox<Transaction>(_transactionBoxName);
    } catch (e) {
      // Older builds stored Transactions under typeId 0 (clashing with Expense).
      // The box is a rebuildable SMS cache, so drop it and let it re-sync.
      log('Transaction box incompatible ($e); rebuilding from SMS');
      await Hive.deleteBoxFromDisk(_transactionBoxName);
      _transactionBox = await Hive.openBox<Transaction>(_transactionBoxName);
    }
    await _loadKeywords(); // Load keywords during initialization
    _isInitialized = true;
    log('SmsService initialized with ${_cachedKeywords.length} keywords');
    _startSmsPolling(); // Start polling after init
  }

  Future<void> _loadKeywords() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      log('No user signed in - using default keywords only');
      _cachedKeywords = List.from(_defaultKeywords);
      return;
    }
    log('Loading keywords for user: $userId');
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('sms_keywords')
          .orderBy('timestamp', descending: true)
          .get();
      final userKeywords =
          snapshot.docs.map((doc) => doc['keyword'] as String).toList();
      _cachedKeywords = [..._defaultKeywords, ...userKeywords]
          .map((k) => k.toLowerCase())
          .toSet()
          .toList();
      log('Loaded keywords (default + user): $_cachedKeywords');
    } catch (e) {
      log('Error loading keywords: $e');
      _cachedKeywords = List.from(_defaultKeywords);
    }
  }

  Future<int> initializeSmsStore() async {
    if (!_isInitialized) {
      await init();
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      log('No user signed in for SMS store initialization');
      return 0;
    }

    if (_cachedKeywords.isEmpty) {
      log('No keywords available during initialization');
      throw Exception('NO_KEYWORDS_AVAILABLE');
    }

    await _loadKeywords(); // The user may have signed in since init().

    final lastSync = _transactionBox.get(_lastSyncKey)?.date;
    final prefs = await SharedPreferences.getInstance();
    final backfilled = prefs.getBool(_backfillKey) == true;
    int newTransactions = 0;
    if (lastSync == null || !backfilled) {
      // First run, or first run since gaps could exist in the store: re-read
      // the inbox. Messages already stored are skipped.
      log('Full SMS sync (first run: ${lastSync == null})');
      final started = DateTime.now();
      newTransactions = await _fullSmsSync();
      if (await Permission.sms.status.isGranted) {
        await _markSynced(started);
        await prefs.setBool(_backfillKey, true);
      }
      log('SMS store updated with $newTransactions new messages');
    } else {
      newTransactions = await _incrementalSmsSync(DateTime.parse(lastSync));
    }
    return newTransactions;
  }

  Future<void> _markSynced(DateTime at) => _transactionBox.put(
      _lastSyncKey,
      Transaction(
        type: 'sync',
        amount: 0,
        description: 'Last sync timestamp',
        date: at.toIso8601String(),
        transactionId: 'sync_key',
        rawSms: '',
      ));

  /// All inbox and sent messages from [cutoff] onwards, reading page by page
  /// so a busy phone can't push messages past a fixed count.
  Future<List<smsInbox.SmsMessage>> _readMessagesSince(DateTime cutoff) async {
    final found = <smsInbox.SmsMessage>[];
    for (final kind in [smsInbox.SmsQueryKind.inbox, smsInbox.SmsQueryKind.sent]) {
      var start = 0;
      while (true) {
        final page = await _smsQuery.querySms(
          kinds: [kind],
          start: start,
          count: _batchSize,
        );
        found.addAll(
            page.where((m) => m.date != null && !m.date!.isBefore(cutoff)));
        if (page.length < _batchSize ||
            page.last.date?.isBefore(cutoff) == true) {
          break; // Newest first, so everything further is older.
        }
        start += _batchSize;
      }
    }
    return found;
  }

  Future<bool> get hasSmsPermission => Permission.sms.status.isGranted;

  /// Re-reads the inbox for one day and stores anything missing, so a message
  /// an earlier sync missed still appears. Never prompts for permission.
  Future<int> syncInboxForDay(DateTime day) async {
    if (!_isInitialized) await init();
    if (!await hasSmsPermission) return 0;
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    final messages = await _readMessagesSince(start);
    return _saveAllSmsToStore(
        messages.where((m) => m.date!.isBefore(end)).toList());
  }

  Future<int> _fullSmsSync() async {
    if (!await _checkAndRequestSmsPermission()) return 0;

    final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));

    // Query directly on the main isolate. Passing the SMS plugin across a
    // background isolate (compute) is unreliable in release/AOT builds and
    // silently returned nothing there, so the first-run sync loaded no SMS.
    final recent = await _readMessagesSince(sixMonthsAgo);

    final newCount = await _saveAllSmsToStore(recent);
    log('Full sync stored $newCount of ${recent.length} fetched messages');
    return newCount;
  }

  Future<int> _incrementalSmsSync(DateTime lastSyncDate) async {
    if (!await _checkAndRequestSmsPermission()) return 0;

    // Taken before reading, so a message arriving during the read is covered
    // by the next sync.
    final started = DateTime.now();
    final messages =
        await _readMessagesSince(lastSyncDate.subtract(_syncOverlap));
    final count = await _saveAllSmsToStore(messages);
    await _markSynced(started);
    if (count > 0) log('Added $count new SMS to store');
    return count;
  }

  Future<bool> _checkAndRequestSmsPermission() async {
    if (_isRequestingPermissions) {
      log('Permission request already in progress, waiting...');
      while (_isRequestingPermissions) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      return await Permission.sms.status.isGranted;
    }

    _isRequestingPermissions = true;
    try {
      var status = await Permission.sms.status;
      if (status.isGranted) {
        log('SMS permission already granted');
        return true;
      }

      if (status.isPermanentlyDenied) {
        log('SMS permission permanently denied, opening settings');
        await openAppSettings();
        return false;
      }

      Map<Permission, PermissionStatus> statuses = await [
        Permission.sms,
        // Add other permissions if needed, e.g., Permission.storage
      ].request();

      if (statuses[Permission.sms]!.isGranted) {
        log('SMS permission granted');
        return true;
      } else {
        log('SMS permission denied');
        return false;
      }
    } catch (e) {
      log('Error requesting SMS permission: $e');
      return false;
    } finally {
      _isRequestingPermissions = false;
    }
  }

  Future<int> _saveAllSmsToStore(List<smsInbox.SmsMessage> messages) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return 0;

    final existingIds =
        _transactionBox.values.map((t) => t.transactionId).toSet();
    int newCount = 0;

    for (var msg in messages) {
      final originalTransactionId =
          'SMS_${msg.sender ?? "unknown"}_${msg.date!.millisecondsSinceEpoch}';
      final hiveKey =
          md5.convert(utf8.encode(originalTransactionId)).toString();

      if (!existingIds.contains(originalTransactionId) &&
          !_transactionBox.containsKey(hiveKey)) {
        final transaction = Transaction(
          type: 'unknown',
          amount: 0,
          description: msg.body ?? '',
          date: msg.date!.toIso8601String(),
          transactionId: originalTransactionId,
          rawSms: msg.body ?? '',
          categoryId: null, // Initially uncategorized
        );
        await _transactionBox.put(hiveKey, transaction);
        existingIds.add(originalTransactionId);
        newCount++;
      }
    }

    return newCount;
  }

  void _startSmsPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(Duration(seconds: 60), (timer) async {
      if (!_isInitialized) return;
      final lastSync = _transactionBox.get(_lastSyncKey)?.date;
      if (lastSync != null) {
        await _incrementalSmsSync(DateTime.parse(lastSync));
      }
    });
    log('SMS polling started');
  }

  void _stopSmsPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    log('SMS polling stopped');
  }

  Future<Map<String, int>> fetchTransactions(
    String fetchType,
    DateTime referenceDate, {
    DateTime? rangeEnd,
  }) async {
    log('Starting fetchTransactions: fetchType=$fetchType, referenceDate=$referenceDate, rangeEnd=$rangeEnd');

    if (!_isInitialized) {
      await init(); // Ensure initialization if called directly
    }

    // 1. Permission check
    if (!await _checkAndRequestSmsPermission()) {
      throw Exception('SMS permission denied');
    }

    // 2. Load keywords
    if (!_keywordsLoaded || _cachedKeywords.isEmpty) {
      await _loadKeywords();
      if (_cachedKeywords.isEmpty) {
        throw Exception('NO_KEYWORDS_AVAILABLE');
      }
      _keywordsLoaded = true;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not signed in');
    }

    // 3. Set up date range
    DateTime startDate;
    DateTime endDate;

    switch (fetchType.toLowerCase()) {
      case 'day':
        startDate = DateTime(referenceDate.year, referenceDate.month,
            referenceDate.day, 0, 0, 0);
        endDate = DateTime(referenceDate.year, referenceDate.month,
            referenceDate.day, 23, 59, 59, 999);
        break;
      case 'range':
        if (rangeEnd == null) {
          throw Exception('Range fetch requires an end date');
        }
        startDate = DateTime(
            referenceDate.year, referenceDate.month, referenceDate.day);
        endDate =
            DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
        if (startDate.isAfter(endDate)) {
          final temp = startDate;
          startDate = endDate;
          endDate = temp;
        }
        break;
      case 'month':
        startDate = DateTime(referenceDate.year, referenceDate.month, 1);
        endDate = DateTime(
            referenceDate.year, referenceDate.month + 1, 0, 23, 59, 59);
        break;
      default:
        throw Exception('Invalid fetch type: $fetchType');
    }

    // 4. Fetch transactions from Hive store
    final allMessages = _transactionBox.values
        .where((t) => t.transactionId != 'sync_key')
        .where((t) {
      final date = DateTime.parse(t.date);
      return !date.isBefore(startDate) && !date.isAfter(endDate);
    }).toList();

    // 5. Parse transactions with enhanced logic from Code 2
    final transactions = <_ParsedSms>[];
    for (final t in allMessages) {
      final parsed = parseTransactionEnhanced(
          t.rawSms, DateTime.parse(t.date), t.transactionId);
      if (parsed != null) transactions.add(_ParsedSms(parsed, t.transactionId));
    }

    // 6. Sync with Firestore including categoryId and timestamp
    await _syncWithFirestoreEnhanced(transactions);

    log('Fetched ${transactions.length} transactional SMS from ${allMessages.length} stored messages');
    return {
      'parsed': transactions.length,
      'unparsed': allMessages.length - transactions.length
    };
  }

  Transaction? parseTransactionEnhanced(
          String body, DateTime msgDate, String originalTransactionId) =>
      parseSms(body, msgDate, originalTransactionId, _cachedKeywords);

  static final RegExp _sensitiveWords = RegExp(
      r'\b(otp|password|passcode|pin|verification)\b|expires in',
      caseSensitive: false);
  static final RegExp _completedWords = RegExp(
      r'\b(confirmed|successful|successfully|received|sent|paid|debited|credited|withdrawn|deposited)\b',
      caseSensitive: false);
  static final RegExp _currencyAmount = RegExp(
      r'(?<![A-Za-z])(?:kshs?|kes|shs|usd|ugx|tzs)\.?\s*(\d[\d,]*(?:\.\d{1,2})?)',
      caseSensitive: false);
  static final RegExp _bareAmount = RegExp(
      r'(?<![\w.,/:-])(\d{1,9}(?:,\d{3})*(?:\.\d{1,2})?)(?![\w/:])');

  /// Turns an SMS into a transaction, or null if it isn't one.
  static Transaction? parseSms(String body, DateTime msgDate,
      String originalTransactionId, List<String> keywords) {
    final lowerBody = body.toLowerCase();

    // Check if the SMS contains any user-defined keywords
    bool hasKeywordMatch =
        keywords.any((keyword) => lowerBody.contains(keyword.toLowerCase()));
    if (!hasKeywordMatch) {
      log('No user-defined keyword match found');
      return null;
    }

    // Find the amount: a currency-marked figure first, then the user's own
    // short keywords, then any standalone number.
    Match? amountMatch = _currencyAmount.firstMatch(body);
    if (amountMatch == null) {
      final userCurrencies = keywords
          .where((k) =>
              k.length <= 5 &&
              !k.contains(' ') &&
              !_defaultKeywords.contains(k.toLowerCase()))
          .map((k) => RegExp.escape(k.toLowerCase()))
          .toList();
      if (userCurrencies.isNotEmpty) {
        amountMatch = RegExp(
                r'(?<![A-Za-z])(?:' +
                    userCurrencies.join('|') +
                    r')\.?\s*(\d[\d,]*(?:\.\d{1,2})?)',
                caseSensitive: false)
            .firstMatch(body);
      }
    }
    final hasMarkedAmount = amountMatch != null;

    // OTPs and security notices are not transactions, but a real payment
    // alert may carry a footer like "never share your PIN".
    if (_sensitiveWords.hasMatch(body) &&
        !(hasMarkedAmount && _completedWords.hasMatch(body))) {
      log('Excluded non-transactional SMS (OTP/verification)');
      return null;
    }

    amountMatch ??= _bareAmount.firstMatch(body);
    if (amountMatch == null) {
      log('No valid amount found');
      return null;
    }

    final double? amount =
        double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      log('Invalid amount: ${amountMatch.group(1)}');
      return null;
    }

    // An unmarked small number is more likely a count or date than money.
    if (!hasMarkedAmount &&
        amount < 10 &&
        !(lowerBody.contains('airtime') && amount >= 5)) {
      log('Amount too small to be a transaction: $amount');
      return null;
    }

    // Determine transaction type (original logic)
    final incomeKeywords = [
      'received',
      'credited',
      'deposit',
      'added',
      'salary',
      'refund'
    ];
    final expenseKeywords = [
      'sent',
      'paid',
      'debited',
      'withdrawn',
      'transfer',
      'purchase',
      'charged',
      'airtime',
      'paybill'
    ];

    bool hasIncomeKeyword = incomeKeywords
        .any((k) => lowerBody.contains(k) && keywords.contains(k));
    bool hasExpenseKeyword = expenseKeywords
        .any((k) => lowerBody.contains(k) && keywords.contains(k));

    String type;
    if (hasExpenseKeyword && !hasIncomeKeyword) {
      type = 'Expense';
    } else if (hasIncomeKeyword && !hasExpenseKeyword) {
      type = 'Income';
    } else if (hasIncomeKeyword && hasExpenseKeyword) {
      int lastIncomePos = incomeKeywords
          .where((k) => lowerBody.contains(k))
          .map((k) => lowerBody.lastIndexOf(k))
          .reduce((a, b) => a > b ? a : b);
      int lastExpensePos = expenseKeywords
          .where((k) => lowerBody.contains(k))
          .map((k) => lowerBody.lastIndexOf(k))
          .reduce((a, b) => a > b ? a : b);
      type = lastExpensePos > lastIncomePos ? 'Expense' : 'Income';
    } else if (lowerBody.contains('paybill') &&
        lowerBody.contains('successful')) {
      type = 'Expense';
    } else {
      type = 'Unknown';
    }

    // Parse description
    String description = '';
    RegExp nameRegex = RegExp(r'(?:from|to)\s+([A-Za-z\s\d\-]+(?:\d{6,10})?)',
        caseSensitive: false);
    var nameMatch = nameRegex.firstMatch(body);
    if (nameMatch != null) {
      description = nameMatch.group(1)!.trim();
    } else {
      int amountEnd = amountMatch.end;
      description = body.substring(amountEnd).trim();
      description = description.split('New M-PESA balance').first;
      description = description.split('Transaction cost').first;
      description = description.split('LOOP Ref').first;
    }

    const int maxLength = 25;
    if (description.length > maxLength) {
      description = '${description.substring(0, maxLength - 3)}...';
    }
    if (description.isEmpty) {
      description = type == 'Income' ? 'Received payment' : 'Payment sent';
    }

    // Parse transaction ID
    // Must be a whole token with a digit, so plain words ("Transaction
    // completed", "paid SUPERMARKET") never become an id shared by many SMS.
    RegExp refRegex = RegExp(
        r'\b(?:Ref\.?|ID|Transaction|Code)\s*((?=[A-Z0-9]*\d)[A-Z0-9]{8,12})\b',
        caseSensitive: false);
    var refMatch = refRegex.firstMatch(body);
    String transactionId = originalTransactionId;

    if (refMatch != null) {
      transactionId = refMatch.group(1)!;
    }

    return Transaction(
      type: type,
      amount: amount,
      description: description,
      date: msgDate.toIso8601String(),
      transactionId: transactionId,
      rawSms: body,
      categoryId: null, // Initially uncategorized
    );
  }

  /// Returns true if within a 7-day trial window.
  Future<bool> _isInTrial() async {
    final prefs = await SharedPreferences.getInstance();
    final startStr = prefs.getString('trial_start');
    if (startStr == null) return false;
    final start = DateTime.parse(startStr);
    return DateTime.now().difference(start) < const Duration(days: 7);
  }

  static String _smsKey(String? date, String? rawSms) => '$date|$rawSms';

  // Enhanced Firestore sync function with categoryId and timestamp
  Future<void> _syncWithFirestoreEnhanced(List<_ParsedSms> items) async {
    // only sync to cloud if user is premium OR in trial
    final isPremium = await _subscriptionService.hasPremiumFeatures();
    final inTrial = await _isInTrial(); // if you implemented the trial logic
    if (!isPremium && !inTrial) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || items.isEmpty) return;

    final col =
        _firestore.collection('users').doc(userId).collection('transactions');

    // What's already there for these dates: the same SMS is never added twice.
    final dates = items.map((p) => p.tx.date).toList()..sort();
    final snapshot = await col
        .where('date', isGreaterThanOrEqualTo: dates.first)
        .where('date', isLessThanOrEqualTo: dates.last)
        .get();
    final usedIds = <String>{};
    final seenSms = <String>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      usedIds.add(doc.id);
      seenSms.add(_smsKey(data['date'] as String?, data['rawSms'] as String?));
    }

    var batch = _firestore.batch();
    const int batchSize = 20;
    int batchCount = 0;

    for (final item in items) {
      final t = item.tx;
      if (!seenSms.add(_smsKey(t.date, t.rawSms))) continue;

      // Two different SMS can quote the same reference. Each keeps its own
      // document, falling back to the id that is unique to the message.
      var id = t.transactionId;
      if (id != item.storedId && await _idTaken(col, id, usedIds)) {
        id = item.storedId;
      }
      if (!usedIds.add(id)) continue;

      batch.set(col.doc(id), {
        'type': t.type,
        'amount': t.amount,
        'description': t.description,
        'date': t.date,
        'rawSms': t.rawSms,
        'transactionId': id,
        'categoryId': null, // Added from Code 2, can be updated later via app logic
        'timestamp': FieldValue.serverTimestamp(), // Added from Code 2
      });
      batchCount++;

      if (batchCount >= batchSize) {
        await batch.commit();
        batch = _firestore.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    log('Synced ${items.length} transactions to Firestore');
  }

  Future<bool> _idTaken(CollectionReference<Map<String, dynamic>> col,
      String id, Set<String> usedIds) async {
    if (usedIds.contains(id)) return true;
    try {
      return (await col.doc(id).get()).exists;
    } catch (e) {
      log('Could not check id $id: $e');
      return true; // Safer than overwriting another transaction.
    }
  }

  Future<void> addKeyword(String keyword) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      log('No user signed in - cannot add keyword');
      throw Exception('User not signed in');
    }
    log('Adding keyword: $keyword for user: $userId');
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('sms_keywords')
        .get();
    if (snapshot.docs.length >= 20) {
      log('Keyword limit reached (20)');
      throw Exception('Maximum 20 keywords allowed');
    }
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('sms_keywords')
          .add({
        'keyword': keyword.trim().toLowerCase(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      await _loadKeywords();
      log('Keyword added successfully: $keyword');
    } catch (e) {
      log('Error adding keyword: $e');
      rethrow;
    }
  }

  Future<void> deleteKeyword(String keyword) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    if (_cachedKeywords.contains(keyword)) {
      _cachedKeywords.remove(keyword);
      await _firestore.collection('users').doc(userId).update({
        'sms_keywords': _cachedKeywords,
      });
      log('Deleted keyword: $keyword');
    }
  }

  List<String> get keywords => List.unmodifiable(_cachedKeywords);

  // Update local transaction with categoryId
  Future<void> updateTransactionCategory(String transactionId, String? categoryId) async {
    if (!_isInitialized) {
      await init();
    }

    // Find the transaction in local storage by transactionId
    final transaction = _transactionBox.values.firstWhere(
      (t) => t.transactionId == transactionId,
      orElse: () => throw Exception('Transaction not found in local storage'),
    );

    // Create updated transaction with new categoryId
    final updatedTransaction = transaction.withCategoryId(categoryId);
    
    // Get the Hive key for this transaction
    final hiveKey = _transactionBox.keys.firstWhere(
      (key) => _transactionBox.get(key)?.transactionId == transactionId,
      orElse: () => throw Exception('Transaction key not found'),
    );

    // Update the transaction in Hive
    await _transactionBox.put(hiveKey, updatedTransaction);
    log('Updated transaction $transactionId with categoryId: $categoryId in local storage');
  }

  void dispose() {
    _stopSmsPolling();
    if (_isInitialized) {
      _transactionBox.close();
    }
    log('SmsService disposed');
  }
}
