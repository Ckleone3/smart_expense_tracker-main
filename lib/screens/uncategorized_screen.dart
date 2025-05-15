import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:smart_expense_tracker/services/sms_service.dart';

class UncategorizedScreen extends StatefulWidget {
  const UncategorizedScreen({super.key});

  @override
  _UncategorizedScreenState createState() => _UncategorizedScreenState();
}

class _UncategorizedScreenState extends State<UncategorizedScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 20;
  List<QueryDocumentSnapshot> _transactions = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isInitialLoading = true;
  StreamSubscription<QuerySnapshot>? _streamSubscription;
  DateTime _selectedDate = DateTime.now();
  bool _isSelectionMode = false;
  List<String> _selectedTransactionIds = [];

  @override
  void initState() {
    super.initState();
    _startListeningToStream();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _startListeningToStream() {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    _streamSubscription?.cancel();

    final startOfDay =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));

    _streamSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('categoryId', isNull: true)
        .where('date', isGreaterThanOrEqualTo: startOfDay.toIso8601String())
        .where('date', isLessThanOrEqualTo: endOfDay.toIso8601String())
        .orderBy('date', descending: true)
        .limit(_pageSize)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      setState(() {
        _transactions = snapshot.docs;
        _lastDoc = _transactions.isNotEmpty ? _transactions.last : null;
        _hasMore = snapshot.docs.length == _pageSize;
        _isInitialLoading = false;
        _selectedTransactionIds
            .retainWhere((id) => _transactions.any((t) => t.id == id));
      });
    }, onError: (error) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _transactions = [];
        });
        _showSnackBar(context, 'Stream error: $error');
      }
    });
  }

  Future<void> _fetchMoreTransactions(String userId) async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;

    setState(() => _isLoadingMore = true);

    final startOfDay =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));

    try {
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .where('categoryId', isNull: true)
          .where('date', isGreaterThanOrEqualTo: startOfDay.toIso8601String())
          .where('date', isLessThanOrEqualTo: endOfDay.toIso8601String())
          .orderBy('date', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize)
          .get();

      if (!mounted) return;

      setState(() {
        _transactions.addAll(querySnapshot.docs);
        _lastDoc =
            querySnapshot.docs.isNotEmpty ? querySnapshot.docs.last : null;
        _hasMore = querySnapshot.docs.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        _showSnackBar(context, 'Error fetching more transactions: $e');
      }
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _transactions.clear();
        _lastDoc = null;
        _hasMore = true;
        _isInitialLoading = true;
        _isSelectionMode = false;
        _selectedTransactionIds.clear();
      });
      _startListeningToStream();
    }
  }

  Future<void> _fetchSmsForSelectedDate() async {
    final smsService = Provider.of<SmsService>(context, listen: false);
    try {
      final result = await smsService.fetchTransactions('day', _selectedDate);
      if (result['parsed']! > 0) {
        _showSnackBar(context,
            'Fetched ${result['parsed']} SMS transactions for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}');
      } else {
        _showSnackBar(context,
            'No new SMS transactions found for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}');
      }
    } catch (e) {
      if (e.toString().contains('NO_KEYWORDS_SET')) {
        _showNoKeywordsDialog(context);
      } else {
        _showSnackBar(context, 'Error fetching SMS: $e');
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedTransactionIds.clear();
    });
  }

  void _toggleSelection(String transactionId) {
    setState(() {
      if (_selectedTransactionIds.contains(transactionId)) {
        _selectedTransactionIds.remove(transactionId);
      } else {
        _selectedTransactionIds.add(transactionId);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedTransactionIds = _transactions.map((t) => t.id).toList();
    });
  }

  void _deleteSelectedTransactions(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || _selectedTransactionIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Transactions'),
        content: Text(
            'Are you sure you want to delete ${_selectedTransactionIds.length} selected transaction${_selectedTransactionIds.length > 1 ? 's' : ''}?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final batch = _firestore.batch();
                for (var id in _selectedTransactionIds) {
                  final ref = _firestore
                      .collection('users')
                      .doc(userId)
                      .collection('transactions')
                      .doc(id);
                  batch.delete(ref);
                }
                await batch.commit();
                setState(() {
                  _isSelectionMode = false;
                  _selectedTransactionIds.clear();
                });
                Navigator.pop(context);
                _showSnackBar(context, 'Selected transactions deleted');
              } catch (e) {
                _showSnackBar(context, 'Failed to delete: $e');
                Navigator.pop(context);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showNoKeywordsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Keywords Set'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.info_outline, color: Colors.orange, size: 36),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'To fetch SMS transactions, you need to set up keywords that identify your financial messages.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Examples of keywords:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('• "Ksh" - For Kenyan Shilling transactions'),
                  Text('• "paid" - For payment notifications'),
                  Text('• "sent" - For money transfer messages'),
                  Text('• "received" - For incoming transactions'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
            label: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view transactions')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Uncategorized - ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _pickDate(context),
            tooltip: 'Select Date',
          ),
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: _selectAll,
              tooltip: 'Select All',
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteSelectedTransactions(context),
              tooltip: 'Delete Selected',
            ),
          ],
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.select_all),
            onPressed: _toggleSelectionMode,
            tooltip: _isSelectionMode ? 'Exit Selection' : 'Select Multiple',
          ),
        ],
      ),
      body: _isInitialLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchSmsForSelectedDate();
                setState(() {
                  _transactions.clear();
                  _lastDoc = null;
                  _hasMore = true;
                  _isInitialLoading = true;
                  _isSelectionMode = false;
                  _selectedTransactionIds.clear();
                });
                _startListeningToStream();
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
                        AppBar().preferredSize.height -
                        MediaQuery.of(context).padding.top,
                  ),
                  child: Column(
                    children: [
                      if (_transactions.isEmpty)
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inbox,
                                  size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              const Text(
                                'No uncategorized transactions for this date',
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
                        )
                      else
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final transaction = _transactions[index];
                            final transactionId = transaction.id;
                            final type =
                                transaction['type'] as String? ?? 'Unknown';
                            final amount =
                                transaction['amount'] as double? ?? 0.0;
                            final description =
                                transaction['description'] as String? ??
                                    'No description';
                            final date =
                                transaction['date'] as String? ?? 'No date';
                            final rawSms = transaction['rawSms'] as String? ??
                                'No SMS data';
                            final isSelected =
                                _selectedTransactionIds.contains(transactionId);

                            return _buildTransactionCard(
                              context,
                              transactionId,
                              type,
                              amount,
                              description,
                              date,
                              rawSms,
                              isSelected: isSelected,
                            );
                          },
                        ),
                      if (_hasMore || _isLoadingMore)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: _isLoadingMore
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton(
                                  onPressed: () =>
                                      _fetchMoreTransactions(userId),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  child: const Text('Load More Transactions'),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // Helper Methods
  Widget _buildTransactionCard(
    BuildContext context,
    String transactionId,
    String type,
    double amount,
    String description,
    String date,
    String rawSms, {
    bool isSelected = false,
  }) {
    String formattedDate;
    try {
      final dateTime = DateTime.parse(date);
      formattedDate = DateFormat('HH:mm').format(dateTime);
    } catch (e) {
      try {
        final dateFormat = DateFormat('dd/MM/yy');
        final dateTime = dateFormat.parse(date);
        final adjustedDateTime = DateTime(
          dateTime.year < 100 ? dateTime.year + 2000 : dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
        );
        formattedDate = DateFormat('HH:mm').format(adjustedDateTime);
      } catch (e) {
        formattedDate = 'Invalid Time';
        debugPrint('Failed to parse date "$date": $e');
      }
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isSelected ? Colors.blue.withOpacity(0.2) : null,
      child: ListTile(
        onTap: _isSelectionMode
            ? () => _toggleSelection(transactionId)
            : () => _showTransactionDetails(context, {
                  'type': type,
                  'description': description,
                  'amount': amount,
                  'date': date,
                  'rawSms': rawSms,
                  'transactionId': transactionId,
                }),
        onLongPress: () {
          if (!_isSelectionMode) {
            setState(() {
              _isSelectionMode = true;
              _selectedTransactionIds.add(transactionId);
            });
          }
        },
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$type: $description',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            if (type == 'Unknown' && !_isSelectionMode)
              IconButton(
                icon: const Icon(Icons.help_outline, color: Colors.orange),
                onPressed: () => _updateTransactionType(transactionId, context),
                tooltip: 'Set Transaction Type',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount: ${NumberFormat.currency(symbol: 'Ksh ').format(amount)} - $formattedDate',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.6,
              child: Text(
                'Raw SMS: $rawSms',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        trailing: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelection(transactionId),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _categorizeTransaction(
                        transactionId, type, amount, context),
                    tooltip: 'Categorize',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteTransaction(transactionId, context),
                    tooltip: 'Delete',
                  ),
                ],
              ),
      ),
    );
  }

  Future<List<String>> _fetchCategories(String type) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return [];
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: type)
        .get();
    return snapshot.docs.map((doc) => doc['name'] as String).toList();
  }

  Future<double> _fetchCategoryBalance(
      String userId, String categoryId, double transactionAmount) async {
    // Fetch allocations for the specific category
    final allocationsSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('allocations')
        .where('categoryId', isEqualTo: categoryId)
        .get();

    // Fetch categorized expenses for the specific category
    final transactionsSnapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('transactions')
        .where('type', isEqualTo: 'Expense')
        .where('categoryId', isEqualTo: categoryId)
        .get();

    // Calculate total allocated amount
    double allocatedAmount = 0.0;
    for (var doc in allocationsSnapshot.docs) {
      final amount = (doc['amount'] as num?)?.toDouble() ?? 0.0;
      allocatedAmount += amount;
    }

    // Calculate total spent amount
    double spentAmount = 0.0;
    for (var doc in transactionsSnapshot.docs) {
      final amount = (doc['amount'] as num?)?.toDouble() ?? 0.0;
      spentAmount += amount;
    }

    // Calculate current balance and projected balance after transaction
    final currentBalance = allocatedAmount - spentAmount;
    return currentBalance - transactionAmount; // Return projected balance
  }

  Future<double> _calculateExpensePercentageTotal() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return 0;
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();
    return snapshot.docs.fold<double>(
        0.0, (sum, doc) => sum + ((doc['percentage'] as num?)?.toDouble() ?? 0.0));
  }

  Future<void> _allocateIncome(
      String transactionId, double amount, String userId) async {
    final expenseCategories = await _firestore
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();

    for (var categoryDoc in expenseCategories.docs) {
      final category = categoryDoc.data();
      final double percentage =
          (category['percentage'] as num?)?.toDouble() ?? 0;
      final double allocatedAmount = (amount * percentage) / 100;

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('allocations')
          .add({
        'transactionId': transactionId,
        'categoryId': category['name'],
        'amount': allocatedAmount,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  void _categorizeTransaction(String transactionId, String type, double amount,
      BuildContext context) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showSnackBar(context, 'Please sign in to categorize transactions');
      return;
    }

    final categories = await _fetchCategories(type);
    if (categories.isEmpty) {
      _showSnackBar(
          context, 'No $type categories available. Add some in Settings.');
      return;
    }

    if (type == 'Income') {
      final expenseTotal = await _calculateExpensePercentageTotal();
      if (expenseTotal != 100) {
        _showSnackBar(context,
            'Expense categories must total 100% to categorize income.');
        return;
      }
      await _allocateIncome(transactionId, amount, userId);
    }

    _showCategoryDialog(context, transactionId, type, categories, userId, amount);
  }

  void _deleteTransaction(String transactionId, BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content:
            const Text('Are you sure you want to delete this transaction?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _firestore
                    .collection('users')
                    .doc(userId)
                    .collection('transactions')
                    .doc(transactionId)
                    .delete();
                Navigator.pop(context);
                _showSnackBar(context, 'Transaction deleted');
              } catch (e) {
                _showSnackBar(context, 'Failed to delete: $e');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _updateTransactionType(String transactionId, BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Transaction Type'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDialogButton(
              label: 'Income',
              onPressed: () =>
                  _updateType(transactionId, 'Income', context, userId),
            ),
            const SizedBox(height: 12),
            _buildDialogButton(
              label: 'Expense',
              onPressed: () =>
                  _updateType(transactionId, 'Expense', context, userId),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showTransactionDetails(
      BuildContext context, Map<String, dynamic> transactionData) {
    String formattedDate;
    try {
      final dateTime = DateTime.parse(transactionData['date']);
      formattedDate = DateFormat('HH:mm').format(dateTime);
    } catch (e) {
      try {
        final dateFormat = DateFormat('dd/MM/yy');
        final dateTime = dateFormat.parse(transactionData['date']);
        final adjustedDateTime = DateTime(
          dateTime.year < 100 ? dateTime.year + 2000 : dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
        );
        formattedDate = DateFormat('HH:mm').format(adjustedDateTime);
      } catch (e) {
        formattedDate = 'Invalid Time';
        debugPrint('Failed to parse date "${transactionData['date']}": $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transaction Details'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow(
                  'Amount',
                  NumberFormat.currency(symbol: 'Ksh ')
                      .format(transactionData['amount'])),
              _buildDetailRow('Time', formattedDate),
              _buildDetailRow(
                  'Transaction ID', transactionData['transactionId']),
              const SizedBox(height: 8),
              const Text('Raw SMS:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                transactionData['rawSms'],
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogButton(
      {required String label, required VoidCallback onPressed}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showInsufficientFundsDialog(BuildContext context, String category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insufficient Funds'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning, color: Colors.red, size: 36),
        content: Text(
          'There are insufficient funds in "$category" to categorize this expense.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showCategoryDialog(BuildContext context, String transactionId, String type,
      List<String> categories, String userId, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select $type Category'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: categories.map((category) {
              return ListTile(
                title: Text(category),
                onTap: () async {
                  if (type == 'Expense') {
                    // Check balance only when saving an expense
                    final projectedBalance =
                        await _fetchCategoryBalance(userId, category, amount);
                    if (projectedBalance < 0) {
                      Navigator.pop(context); // Close the category dialog
                      _showInsufficientFundsDialog(context, category);
                      return;
                    }
                  }

                  try {
                    await _firestore
                        .collection('users')
                        .doc(userId)
                        .collection('transactions')
                        .doc(transactionId)
                        .update({'categoryId': category});
                    Navigator.pop(context);
                    _showSnackBar(context, 'Transaction categorized as $category');
                  } catch (e) {
                    _showSnackBar(context, 'Failed to categorize: $e');
                  }
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _updateType(String transactionId, String newType, BuildContext context,
      String userId) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .doc(transactionId)
          .update({'type': newType});
      Navigator.pop(context);
      _showSnackBar(context, 'Transaction set as $newType');
    } catch (e) {
      _showSnackBar(context, 'Failed to update type: $e');
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}