import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:developer';
import 'package:provider/provider.dart';
import 'package:smart_expense_tracker/services/subscription_service.dart';
import 'package:smart_expense_tracker/services/sms_service.dart' as sms;
import 'package:hive/hive.dart';

class UncategorizedScreen extends StatefulWidget {
  const UncategorizedScreen({super.key});

  @override
  _UncategorizedScreenState createState() => _UncategorizedScreenState();
}

class _UncategorizedScreenState extends State<UncategorizedScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;

  List<dynamic> _transactions = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  StreamSubscription<QuerySnapshot>? _streamSubscription;
  bool _isCategorizing = false;
  String? _categorizingTransactionId;

  DateTime _selectedDate = DateTime.now();
  bool _isSelectionMode = false;
  List<String> _selectedTransactionIds = [];

  bool _isPremium = false;
  late final sms.SmsService _smsService;
  late final SubscriptionService _subscriptionService;
  StreamSubscription<SubscriptionTier>? _subscriptionStream;

  @override
  void initState() {
    super.initState();
    _smsService = Provider.of<sms.SmsService>(context, listen: false);
    _subscriptionService =
        Provider.of<SubscriptionService>(context, listen: false);
    // Listen for tier changes
    _subscriptionStream = _subscriptionService.tierStream().listen((tier) {
      final was = _isPremium;
      setState(() => _isPremium = tier == SubscriptionTier.premium);
      if (was != _isPremium) _resetAndReload();
    });
    // Initial load
    _subscriptionService.hasPremiumFeatures().then((isPremium) {
      setState(() => _isPremium = isPremium);
      if (_isPremium) {
        _startListeningToStream();
      } else {
        _loadLocalTransactions();
      }
    });
  }

  void _resetAndReload() {
    setState(() {
      _transactions.clear();
      _lastDoc = null;
      _hasMore = true;
      _isInitialLoading = true;
      _isSelectionMode = false;
      _selectedTransactionIds.clear();
    });
    if (_isPremium) {
      _startListeningToStream();
    } else {
      _loadLocalTransactions();
    }
  }

  @override
  void dispose() {
    _subscriptionStream?.cancel();
    _streamSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  //
  // ─── PREMIUM (FIRESTORE) ─────────────────────────────────────────────────────
  //

  void _startListeningToStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _streamSubscription?.cancel();
    final start =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    _streamSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .where('categoryId', isNull: true)
        .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
        .where('date', isLessThanOrEqualTo: end.toIso8601String())
        .orderBy('date', descending: true)
        .limit(_pageSize)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        // For premium users, replace the entire list since it's paginated
        _transactions = snap.docs;
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length == _pageSize;
        _isInitialLoading = false;
        _selectedTransactionIds.retainWhere((id) =>
            _transactions.any((t) => (t as QueryDocumentSnapshot).id == id));
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _isInitialLoading = false;
        _transactions.clear();
      });
      _showSnackBar(context, 'Stream error: $e');
    });
  }

  Future<void> _fetchMoreTransactions(String uid) async {
    if (!_isPremium || _isLoadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    final start =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    try {
      final qs = await _firestore
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .where('categoryId', isNull: true)
          .where('date', isGreaterThanOrEqualTo: start.toIso8601String())
          .where('date', isLessThanOrEqualTo: end.toIso8601String())
          .orderBy('date', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();
      setState(() {
        _transactions.addAll(qs.docs);
        _lastDoc = qs.docs.isNotEmpty ? qs.docs.last : null;
        _hasMore = qs.docs.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      _showSnackBar(context, 'Error fetching more: $e');
    }
  }

  //
  // ─── LOCAL (HIVE) ──────────────────────────────────────────────────────────────
  //

  Future<void> _loadLocalTransactions() async {
    if (!mounted) return;
    setState(() => _isInitialLoading = true);
    try {
      final start =
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = start
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));

      // 1) Grab all Hive‐stored SMS in that day that are uncategorized (categoryId is null)
      final rawList = _smsService.transactionBox.values.where((h) {
        final d = DateTime.parse(h.date);
        return !d.isBefore(start) && !d.isAfter(end) && h.categoryId == null;
      }).toList();

      // 2) Re‐parse each through your enhanced parser
      final parsed = rawList
          .map((h) => _smsService.parseTransactionEnhanced(
                h.rawSms,
                DateTime.parse(h.date),
                h.transactionId,
              ))
          .where((t) => t != null)
          .cast<sms.Transaction>()
          .toList();

      // 3) Sort newest first
      parsed.sort(
          (a, b) => DateTime.parse(b.date).compareTo(DateTime.parse(a.date)));

      // 4) Update UI
      setState(() {
        _transactions = parsed;
        _hasMore = false;
        _isInitialLoading = false;
        _selectedTransactionIds
            .retainWhere((id) => parsed.any((t) => t.transactionId == id));
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _transactions = [];
        });
        _showSnackBar(context, 'Error loading transactions: $e');
      }
    }
  }

  //
  // ─── SHARED UI + SMS FETCH ────────────────────────────────────────────────────
  //

  Future<void> _pickDate(BuildContext c) async {
    final dt = await showDatePicker(
      context: c,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (dt != null && dt != _selectedDate) {
      setState(() {
        _selectedDate = dt;
        _transactions.clear();
        _lastDoc = null;
        _hasMore = true;
        _isInitialLoading = true;
        _isSelectionMode = false;
        _selectedTransactionIds.clear();
      });
      if (_isPremium) {
        _startListeningToStream();
      } else {
        _loadLocalTransactions();
      }
    }
  }

  Future<void> _fetchSmsForSelectedDate() async {
    try {
      // In case the box was closed, re-initialize the service (re-opens Hive)
      await _smsService.init();
    } catch (_) {
      // ignore any “already initialized” errors
    }

    try {
      final result = await _smsService.fetchTransactions('day', _selectedDate);
      final parsed = result['parsed']!;

      _showSnackBar(
          context,
          parsed > 0
              ? 'Fetched $parsed SMS transactions for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'
              : 'No new SMS transactions for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}');

      if (!_isPremium) {
        await _loadLocalTransactions();
      }
    } on HiveError {
      // box still closed? force re-open and retry once
      await _smsService.init();
      return _fetchSmsForSelectedDate();
    } catch (e) {
      if (e.toString().contains('NO_KEYWORDS_SET')) {
        _showNoKeywordsDialog(context);
      } else {
        _showSnackBar(context, 'Error fetching SMS: $e');
      }
    }
  }

  void _selectAll() {
    setState(() {
      if (_isPremium) {
        _selectedTransactionIds =
            _transactions.map((t) => (t as QueryDocumentSnapshot).id).toList();
      } else {
        _selectedTransactionIds = _transactions
            .cast<sms.Transaction>()
            .map((tx) => tx.transactionId)
            .toList();
      }
    });
  }

  void _deleteSelectedTransactions(BuildContext c) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _selectedTransactionIds.isEmpty) return;
    showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected'),
        content: Text(
          'Delete ${_selectedTransactionIds.length} selected transaction'
          '${_selectedTransactionIds.length > 1 ? 's' : ''}?',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final batch = _firestore.batch();
                for (var id in _selectedTransactionIds) {
                  batch.delete(_firestore
                      .collection('users')
                      .doc(uid)
                      .collection('transactions')
                      .doc(id));
                }
                await batch.commit();
                setState(() {
                  _isSelectionMode = false;
                  _selectedTransactionIds.clear();
                });
                Navigator.pop(ctx);
                _showSnackBar(context, 'Deleted selected');
              } catch (e) {
                Navigator.pop(ctx);
                _showSnackBar(context, 'Failed to delete: $e');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }

  void _showNoKeywordsDialog(BuildContext c) {
    showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('No Keywords Set'),
        icon: const Icon(Icons.info_outline, color: Colors.orange, size: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'To fetch SMS transactions, you need keywords.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 12),
            Text('Examples: "Ksh", "paid", "sent", "received"'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Go to Settings'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext ctx, String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  //
  // ─── BUILD ─────────────────────────────────────────────────────────────────────
  //

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
          body: Center(child: Text('Please sign in to view transactions')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Uncategorized — ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _pickDate(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (_isPremium) {
                _startListeningToStream(); // Force stream restart for premium users
              } else {
                await _loadLocalTransactions(); // Refresh local data for free users
              }
            },
            tooltip: 'Refresh transactions',
          ),
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteSelectedTransactions(context),
            ),
          ],
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.select_all),
            onPressed: () =>
                setState(() => _isSelectionMode = !_isSelectionMode),
          ),
        ],
      ),
      body: _isInitialLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                // 1) always pull-to-refresh the SMS fetch
                await _fetchSmsForSelectedDate();
                // 2) then refresh the transaction list to remove categorized items
                if (_isPremium) {
                  _startListeningToStream(); // Force stream restart for premium users
                } else {
                  await _loadLocalTransactions(); // Refresh local data for free users
                }
              },
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  // ── EMPTY STATE ─────────────────────────────
                  if (_transactions.isEmpty)
                    SizedBox(
                      height: MediaQuery.of(context).size.height -
                          AppBar().preferredSize.height -
                          MediaQuery.of(context).padding.top,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.inbox,
                                size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No uncategorized transactions',
                              style:
                                  TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pull down to fetch SMS for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── LIST ITEMS ──────────────────────────────
                  if (_transactions.isNotEmpty)
                    ...List.generate(_transactions.length, (i) {
                      if (_isPremium) {
                        final doc = _transactions[i] as QueryDocumentSnapshot;
                        return _buildTransactionCard(
                          context,
                          doc.id,
                          doc['type'] as String? ?? 'Unknown',
                          doc['amount'] as double? ?? 0.0,
                          doc['description'] as String? ?? 'No description',
                          doc['date'] as String? ?? '',
                          doc['rawSms'] as String? ?? '',
                          isSelected: _selectedTransactionIds.contains(doc.id),
                        );
                      } else {
                        final localTx = _transactions[i] as sms.Transaction;
                        return _buildTransactionCard(
                          context,
                          localTx.transactionId,
                          localTx.type,
                          localTx.amount,
                          localTx.description,
                          localTx.date,
                          localTx.rawSms,
                          isSelected: _selectedTransactionIds
                              .contains(localTx.transactionId),
                        );
                      }
                    }),

                  // ── LOAD MORE BUTTON ───────────────────────
                  if (_hasMore || _isLoadingMore)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _isLoadingMore
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                              onPressed: () => _fetchMoreTransactions(uid),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Load More Transactions'),
                            ),
                    ),
                ],
              ),
            ),
    );
  }

  //
  // ─── CARD + CATEGORIZATION ────────────────────────────────────────────────────
  //

  Widget _buildTransactionCard(
    BuildContext ctxt,
    String id,
    String type,
    double amount,
    String description,
    String date,
    String rawSms, {
    bool isSelected = false,
  }) {
    String time;
    try {
      time = DateFormat('HH:mm').format(DateTime.parse(date));
    } catch (_) {
      time = 'Invalid';
    }

    final bool isCurrentlyCategorizing = _isCategorizing && _categorizingTransactionId == id;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isSelected ? Colors.blue.withOpacity(0.2) : null,
      child: ListTile(
        leading: isCurrentlyCategorizing
            ? const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : type == 'Income'
                ? CircleAvatar(
                    backgroundColor: Colors.green[100],
                    child: const Icon(Icons.arrow_downward,
                        color: Colors.green, size: 20),
                  )
                : type == 'Expense'
                    ? CircleAvatar(
                        backgroundColor: Colors.red[100],
                        child: const Icon(Icons.arrow_upward,
                            color: Colors.red, size: 20),
                      )
                    : CircleAvatar(
                        backgroundColor: Colors.grey[200],
                        child: const Icon(Icons.help_outline,
                            color: Colors.grey, size: 20),
                      ),
        onTap: _isSelectionMode
            ? () => setState(() {
                  if (isSelected) {
                    _selectedTransactionIds.remove(id);
                  } else {
                    _selectedTransactionIds.add(id);
                  }
                })
            : isCurrentlyCategorizing
                ? null // Disable tap while categorizing
                : () => _showDetails(ctxt, {
                      'transactionId': id,
                      'type': type,
                      'amount': amount,
                      'date': date,
                      'rawSms': rawSms,
                    }),
        onLongPress: isCurrentlyCategorizing
            ? null // Disable long press while categorizing
            : () => setState(() {
                  _isSelectionMode = true;
                  _selectedTransactionIds.add(id);
                }),
        title: Row(
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: isCurrentlyCategorizing
                          ? 'Categorizing...'
                          : type == 'Income'
                              ? 'Income'
                              : type == 'Expense'
                                  ? 'Expense'
                                  : type,
                      style: TextStyle(
                        color: isCurrentlyCategorizing
                            ? Colors.grey
                            : type == 'Income'
                                ? Colors.green
                                : type == 'Expense'
                                    ? Colors.red
                                    : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (!isCurrentlyCategorizing) ...[
                      TextSpan(
                        text: ': $description',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.normal,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (type == 'Unknown' && !_isSelectionMode && !isCurrentlyCategorizing)
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.orange),
                onPressed: () => _updateTransactionType(id, ctxt),
                tooltip: 'Set Type',
              ),
          ],
        ),
        subtitle: Text(
          isCurrentlyCategorizing
              ? 'Please wait while categorizing transaction...'
              : 'Amount: ${NumberFormat.currency(symbol: 'Ksh ').format(amount)} — $time\nRaw: $rawSms',
          style: TextStyle(
            fontSize: 12,
            color: isCurrentlyCategorizing ? Colors.grey : null,
          ),
        ),
        trailing: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: isCurrentlyCategorizing
                    ? null // Disable checkbox while categorizing
                    : (_) => setState(() {
                          if (isSelected) {
                            _selectedTransactionIds.remove(id);
                          } else {
                            _selectedTransactionIds.add(id);
                          }
                        }),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: isCurrentlyCategorizing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit, color: Colors.blue),
                    onPressed: isCurrentlyCategorizing
                        ? null // Disable edit button while categorizing
                        : () => _categorizeTransaction(id, type, amount, ctxt),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: isCurrentlyCategorizing
                        ? null // Disable delete button while categorizing
                        : () => _deleteSingle(ctxt, id),
                  ),
                ],
              ),
      ),
    );
  }

  void _showDetails(BuildContext c, Map<String, dynamic> d) {
    showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('Transaction Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Amount: ${NumberFormat.currency(symbol: 'Ksh ').format(d['amount'])}',
            ),
            Text('Time: ${d['date']}'),
            Text('ID: ${d['transactionId']}'),
            const SizedBox(height: 8),
            Text(d['rawSms'], style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          )
        ],
      ),
    );
  }

  Future<List<String>> _fetchCategories(String type) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('categories')
        .where('type', isEqualTo: type)
        .get();
    return snap.docs.map((d) => d['name'] as String).toList();
  }

  Future<double> _fetchCategoryBalance(
      String uid, String cat, double txAmt) async {
    final allocSnap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('allocations')
        .where('categoryId', isEqualTo: cat)
        .get();
    final txSnap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .where('type', isEqualTo: 'Expense')
        .where('categoryId', isEqualTo: cat)
        .get();
    double alloc = 0, spent = 0;
    for (var d in allocSnap.docs) {
      alloc += (d['amount'] as num?)?.toDouble() ?? 0;
    }
    for (var d in txSnap.docs) {
      spent += (d['amount'] as num?)?.toDouble() ?? 0;
    }
    return alloc - spent - txAmt;
  }

  void _showCategoryDialog(
    BuildContext c,
    String txId,
    String type,
    List<String> categories,
    String uid,
    double amount,
  ) {
    showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text('Select $type Category'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: categories.map((cat) {
              return ListTile(
                title: Text(cat),
                onTap: () async {
                  // Show loading indicator
                  setState(() {
                    _isCategorizing = true;
                    _categorizingTransactionId = txId;
                  });
                  Navigator.pop(ctx); // Close dialog immediately
                  
                  try {
                    if (type == 'Expense') {
                      final proj = await _fetchCategoryBalance(uid, cat, amount);
                      if (proj < 0) {
                        _showSnackBar(context, 'Insufficient funds in $cat');
                        return;
                      }
                    }
                    
                    // Update both categoryId and type in Firestore
                    final updateData = {'categoryId': cat};
                    if (type == 'Unknown') {
                      updateData['type'] = cat; // Use category name as the type for Unknown transactions
                    }
                    
                    await _firestore
                        .collection('users')
                        .doc(uid)
                        .collection('transactions')
                        .doc(txId)
                        .update(updateData);
                    _showSnackBar(context, 'Categorized as $cat');
                    
                    // Update local storage immediately for free users
                    if (!_isPremium) {
                      try {
                        // Update local transaction with new categoryId and type
                        await _smsService.updateTransactionCategory(txId, cat);
                        
                        // If it was an Unknown transaction, also update the type locally
                        if (type == 'Unknown') {
                          await _updateLocalTransactionType(txId, cat);
                        }
                        
                        // Update the transaction in the current list without full refresh
                        _updateTransactionInList(txId, cat, type == 'Unknown' ? cat : type);
                      } catch (e) {
                        log('Error updating local transaction: $e');
                        // Fallback to full refresh if local update fails
                        await _loadLocalTransactions();
                      }
                    } else {
                      // For premium users, remove the transaction from the current list without restarting the stream
                      _removeTransactionFromList(txId);
                    }
                  } catch (e) {
                    _showSnackBar(context, 'Failed to categorize: $e');
                  } finally {
                    // Hide loading indicator
                    if (mounted) {
                      setState(() {
                        _isCategorizing = false;
                        _categorizingTransactionId = null;
                      });
                    }
                  }
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          )
        ],
      ),
    );
  }

  void _categorizeTransaction(
      String txId, String type, double amount, BuildContext ctxt) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnackBar(ctxt, 'Please sign in to categorize transactions');
      return;
    }

    final cats = await _fetchCategories(type);
    if (cats.isEmpty) {
      _showSnackBar(
          ctxt, 'No $type categories available. Add some in Settings.');
      return;
    }

    if (type == 'Income') {
      final total = await _calculateExpensePercentageTotal();
      if (total != 100) {
        _showSnackBar(
            ctxt, 'Expense categories must total 100% to categorize income.');
        return;
      }
      await _allocateIncome(txId, amount, uid);
    }

    _showCategoryDialog(
      ctxt,
      txId,
      type,
      cats,
      uid,
      amount,
    );
  }

  Future<double> _calculateExpensePercentageTotal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();
    return snap.docs.fold<double>(
      0.0,
      (sum, d) => sum + ((d['percentage'] as num?)?.toDouble() ?? 0),
    );
  }

  Future<void> _allocateIncome(String txId, double amount, String uid) async {
    final cats = await _firestore
        .collection('users')
        .doc(uid)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();
    for (var doc in cats.docs) {
      final data = doc.data();
      final perc = (data['percentage'] as num?)?.toDouble() ?? 0;
      final allocAmt = (amount * perc) / 100;
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('allocations')
          .add({
        'transactionId': txId,
        'categoryId': data['name'],
        'amount': allocAmt,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  void _updateTransactionType(String txId, BuildContext ctxt) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showDialog(
      context: ctxt,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Transaction Type'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogButton(
              label: 'Income',
              onPressed: () async {
                await _firestore
                    .collection('users')
                    .doc(uid)
                    .collection('transactions')
                    .doc(txId)
                    .update({'type': 'Income'});
                Navigator.pop(ctx);
                _showSnackBar(ctxt, 'Transaction set as Income');
              },
            ),
            const SizedBox(height: 12),
            _buildDialogButton(
              label: 'Expense',
              onPressed: () async {
                await _firestore
                    .collection('users')
                    .doc(uid)
                    .collection('transactions')
                    .doc(txId)
                    .update({'type': 'Expense'});
                Navigator.pop(ctx);
                _showSnackBar(ctxt, 'Transaction set as Expense');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          )
        ],
      ),
    );
  }

  void _deleteSingle(BuildContext c, String txId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showDialog(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _firestore
                    .collection('users')
                    .doc(uid)
                    .collection('transactions')
                    .doc(txId)
                    .delete();
                Navigator.pop(ctx);
                _showSnackBar(c, 'Deleted');
              } catch (e) {
                _showSnackBar(c, 'Failed to delete: $e');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }

  Widget _buildDialogButton({
    required String label,
    required VoidCallback onPressed,
  }) =>
      ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label),
      );

  // Update transaction type in local storage
  Future<void> _updateLocalTransactionType(String transactionId, String newType) async {
    try {
      final transaction = _smsService.transactionBox.values.firstWhere(
        (t) => t.transactionId == transactionId,
        orElse: () => throw Exception('Transaction not found in local storage'),
      );

      // Create updated transaction with new type
      final updatedTransaction = sms.Transaction(
        type: newType,
        amount: transaction.amount,
        description: transaction.description,
        date: transaction.date,
        transactionId: transaction.transactionId,
        rawSms: transaction.rawSms,
        categoryId: transaction.categoryId,
      );
      
      // Get the Hive key for this transaction
      final hiveKey = _smsService.transactionBox.keys.firstWhere(
        (key) => _smsService.transactionBox.get(key)?.transactionId == transactionId,
        orElse: () => throw Exception('Transaction key not found'),
      );

      // Update the transaction in Hive
      await _smsService.transactionBox.put(hiveKey, updatedTransaction);
      log('Updated transaction $transactionId with type: $newType in local storage');
    } catch (e) {
      log('Error updating local transaction type: $e');
      rethrow;
    }
  }

  // Update transaction in the current list without full refresh
  void _updateTransactionInList(String transactionId, String categoryId, String newType) {
    setState(() {
      for (int i = 0; i < _transactions.length; i++) {
        final transaction = _transactions[i];
        String currentId;
        
        if (_isPremium) {
          currentId = (transaction as QueryDocumentSnapshot).id;
        } else {
          currentId = (transaction as sms.Transaction).transactionId;
        }
        
        if (currentId == transactionId) {
          if (_isPremium) {
            // For premium users, remove it from the list since it's now categorized
            _transactions.removeAt(i);
          } else {
            // For free users, update the local transaction object
            final localTx = transaction as sms.Transaction;
            final updatedTx = sms.Transaction(
              type: newType,
              amount: localTx.amount,
              description: localTx.description,
              date: localTx.date,
              transactionId: localTx.transactionId,
              rawSms: localTx.rawSms,
              categoryId: categoryId,
            );
            _transactions[i] = updatedTx;
          }
          break;
        }
      }
    });
  }

  // Remove transaction from the current list for premium users without restarting stream
  void _removeTransactionFromList(String transactionId) {
    setState(() {
      for (int i = 0; i < _transactions.length; i++) {
        final transaction = _transactions[i];
        final currentId = (transaction as QueryDocumentSnapshot).id;
        
        if (currentId == transactionId) {
          _transactions.removeAt(i);
          _selectedTransactionIds.remove(transactionId);
          break;
        }
      }
    });
  }
}
