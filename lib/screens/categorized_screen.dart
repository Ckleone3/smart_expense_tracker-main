import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:developer';
import 'dart:async';

class CategorizedScreen extends StatefulWidget {
  const CategorizedScreen({super.key});

  @override
  _CategorizedScreenState createState() => _CategorizedScreenState();
}

class _CategorizedScreenState extends State<CategorizedScreen>
    with SingleTickerProviderStateMixin {
  static const int _itemsPerPage = 10;
  String _searchQuery = '';
  late TextEditingController _searchController;
  late TabController _tabController;
  Timer? _debounceTimer;
  DateTime? _selectedMasterExpenseDate; // Date filter for Master Expenses
  DateTime? _selectedMasterIncomeDate; // Date filter for Master Income

  // Cached data to avoid repeated fetches
  Map<String, dynamic>? _cachedData;

  final Map<String, int> _tabPageNumbers = {
    'Income': 0,
    'Expense': 0,
    'Allocations': 0,
    'Master Expenses': 0,
    'Master Income': 0,
  };

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _tabController = TabController(length: 5, vsync: this); // 5 tabs
    _fetchInitialData(); // Fetch data once on init
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final results = await Future.wait([
        _fetchIncomeCategories(userId),
        _fetchAllocations(userId),
        _fetchCurrency(userId),
        _fetchExpenseCategories(userId),
      ]);
      setState(() {
        _cachedData = {
          'incomeCategories': results[0] as List<String>,
          'allocations': results[1] as List<Map<String, dynamic>>,
          'currency': results[2] as String,
          'expenseCategories': results[3] as List<String>,
        };
      });
    } catch (e) {
      log('Error fetching initial data: $e');
    }
  }

  Future<List<String>> _fetchIncomeCategories(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: 'Income')
        .get();
    return snapshot.docs.map((doc) => doc['name'] as String).toList();
  }

  Future<List<String>> _fetchExpenseCategories(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();
    return snapshot.docs.map((doc) => doc['name'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchAllocations(String userId) async {
    final allocationsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('allocations')
        .orderBy('timestamp', descending: true)
        .get();
    return allocationsSnapshot.docs
        .map((doc) => {
              'id': doc.id,
              'categoryId': doc['categoryId'] as String,
              'amount': (doc['amount'] as num?)?.toDouble() ?? 0.0,
              'transactionId': doc['transactionId'] as String,
              'timestamp':
                  (doc['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            })
        .toList();
  }

  Future<String> _fetchCurrency(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('currency')
        .get();
    return doc.exists ? (doc['currency'] as String? ?? 'Ksh') : 'Ksh';
  }

  void _deleteTransaction(String transactionId, String userId) {
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
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('transactions')
                    .doc(transactionId)
                    .delete();
                final allocationsSnapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('allocations')
                    .where('transactionId', isEqualTo: transactionId)
                    .get();
                for (var doc in allocationsSnapshot.docs) {
                  await doc.reference.delete();
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transaction deleted')),
                );
                setState(() {});
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete: $e')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteAllocation(String allocationId, String userId) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Allocation'),
        content: const Text('Are you sure you want to delete this allocation?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('allocations')
                    .doc(allocationId)
                    .delete();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Allocation deleted')),
                );
                setState(() {});
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete allocation: $e')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showTransactionDetails(BuildContext context,
      Map<String, dynamic> transactionData, String userId) {
    String formattedDate;
    try {
      final dateTime = DateTime.parse(transactionData['date']);
      formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
    } catch (e) {
      formattedDate = 'Invalid Date';
      log('Failed to parse date "${transactionData['date']}": $e');
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
              _buildDetailRow('Amount',
                  '${transactionData['currency']} ${transactionData['amount'].toStringAsFixed(2)}'),
              _buildDetailRow('Date', formattedDate),
              _buildDetailRow('Description', transactionData['description']),
              const SizedBox(height: 8),
              const Text('Raw SMS:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(transactionData['rawSms'],
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              if (transactionData['type'] == 'Income')
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('allocations')
                      .where('transactionId',
                          isEqualTo: transactionData['transactionId'])
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const CircularProgressIndicator();
                    }
                    if (snapshot.hasError) {
                      return Text(
                          'Error loading allocations: ${snapshot.error}');
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Text('No allocations found.');
                    }
                    final allocations = snapshot.data!.docs;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Allocations:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ...allocations.map((alloc) {
                          final allocData =
                              alloc.data() as Map<String, dynamic>;
                          return ListTile(
                            title: Text(allocData['categoryId']),
                            subtitle: Text(
                                '${transactionData['currency']} ${(allocData['amount'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () =>
                                  _deleteAllocation(alloc.id, userId),
                            ),
                          );
                        }),
                      ],
                    );
                  },
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = value;
      });
    });
  }

  Future<void> _pickDate(BuildContext context, String tabKey) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: tabKey == 'Master Expenses'
          ? (_selectedMasterExpenseDate ?? DateTime.now())
          : (_selectedMasterIncomeDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (tabKey == 'Master Expenses') {
          _selectedMasterExpenseDate = picked;
        } else if (tabKey == 'Master Income') {
          _selectedMasterIncomeDate = picked;
        }
        _tabPageNumbers[tabKey] = 0; // Reset pagination when date changes
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(
          body: Center(
              child: Text('Please sign in to view categorized transactions')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorized Transactions'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white, // Selected tab text color
          unselectedLabelColor: Colors.white70, // Unselected tab text color
          indicatorColor: Colors.white, // Optional: indicator color
          tabs: const [
            Tab(
                icon: Tooltip(
                    message: 'Income', child: Icon(Icons.arrow_downward)),
                text: 'Income'),
            Tab(
                icon: Tooltip(
                    message: 'Expenses', child: Icon(Icons.arrow_upward)),
                text: 'Expenses'),
            Tab(
                icon: Tooltip(
                    message: 'Allocations', child: Icon(Icons.account_balance)),
                text: 'Allocations'),
            Tab(
                icon: Tooltip(
                    message: 'Master Expenses', child: Icon(Icons.list_alt)),
                text: 'Master Expenses'),
            Tab(
                icon: Tooltip(
                    message: 'Master Income', child: Icon(Icons.list_alt)),
                text: 'Master Income'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('transactions')
            .where('categoryId', isNotEqualTo: null)
            .where('categoryId', isNotEqualTo: 'Uncategorized')
            .orderBy('categoryId')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, transactionSnapshot) {
          if (transactionSnapshot.hasError) {
            return Center(child: Text('Error: ${transactionSnapshot.error}'));
          }
          if (!transactionSnapshot.hasData || _cachedData == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final transactions = transactionSnapshot.data!.docs;
          final currency = _cachedData!['currency'] as String;
          final incomeCategories =
              _cachedData!['incomeCategories'] as List<String>;
          final expenseCategories =
              _cachedData!['expenseCategories'] as List<String>;
          final allAllocations =
              _cachedData!['allocations'] as List<Map<String, dynamic>>;

          // Group transactions by category and type
          final groupedTransactions = {
            'Income': <String, List<QueryDocumentSnapshot>>{},
            'Expense': <String, List<QueryDocumentSnapshot>>{},
          };

          final expenseTotals = <String, double>{};
          final allocatedAmounts = <String, double>{};

          // Calculate allocated amounts
          for (var allocation in allAllocations) {
            allocatedAmounts[allocation['categoryId']] =
                (allocatedAmounts[allocation['categoryId']] ?? 0.0) +
                    allocation['amount'];
          }

          // Initialize category maps
          for (var category in incomeCategories) {
            groupedTransactions['Income']![category] = [];
          }
          for (var category in expenseCategories) {
            groupedTransactions['Expense']![category] = [];
          }

          // Group transactions and calculate totals
          for (var transaction in transactions) {
            final type = transaction['type'] as String? ?? 'Unknown';
            final category = transaction['categoryId'] as String?;
            final amount = transaction['amount'] as double? ?? 0.0;

            if (category != null) {
              if (type == 'Income') {
                groupedTransactions['Income']![category] ??= [];
                groupedTransactions['Income']![category]!.add(transaction);
              } else if (type == 'Expense') {
                groupedTransactions['Expense']![category] ??= [];
                groupedTransactions['Expense']![category]!.add(transaction);
                expenseTotals[category] =
                    (expenseTotals[category] ?? 0.0) + amount;
              }
            }
          }

          // Calculate balances for each expense category
          final balances = expenseTotals.map((category, spent) =>
              MapEntry(category, (allocatedAmounts[category] ?? 0.0) - spent));

          // Group allocations by transaction
          final groupedAllocations = <String, List<Map<String, dynamic>>>{};
          for (var allocation in allAllocations) {
            groupedAllocations[allocation['transactionId']] ??= [];
            groupedAllocations[allocation['transactionId']]!.add(allocation);
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                children: [
                  const SizedBox(height: 8),
                  // Search TextField with responsive width
                  Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxWidth: 600),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search by category',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Tab Content
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTransactionTab('Income',
                            groupedTransactions['Income']!, currency, userId),
                        _buildEnhancedExpenseTab(
                            groupedTransactions:
                                groupedTransactions['Expense']!,
                            currency: currency,
                            userId: userId,
                            balances: balances,
                            allocatedAmounts: allocatedAmounts),
                        _buildAllocationsTab(
                            groupedAllocations, currency, userId),
                        _buildMasterExpenseTab(transactions, currency, userId),
                        _buildMasterIncomeTab(transactions, currency, userId),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTransactionTab(
      String type,
      Map<String, List<QueryDocumentSnapshot>> groupedTransactions,
      String currency,
      String userId,
      {Map<String, double>? balances}) {
    final filteredGroups = groupedTransactions.entries
        .where((entry) =>
            entry.key.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
    final totalItems =
        filteredGroups.fold<int>(0, (sum, entry) => sum + entry.value.length);
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final currentTabPage = _tabPageNumbers[type] ?? 0;
    final startIndex = currentTabPage * _itemsPerPage;
    int currentCount = 0;

    return filteredGroups.isEmpty
        ? const Center(child: Text('No categorized transactions found'))
        : Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: filteredGroups.length,
                  itemBuilder: (context, index) {
                    final category = filteredGroups[index].key;
                    final transactions = filteredGroups[index].value;
                    final categoryTotal = transactions.fold<double>(
                        0.0, (sum, t) => sum + (t['amount'] as double? ?? 0.0));

                    return Semantics(
                      label:
                          'Category $category, ${transactions.length} transactions',
                      child: ExpansionTile(
                        title: Text(category,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'Total: $currency ${categoryTotal.toStringAsFixed(2)}',
                                style: TextStyle(
                                    color: type == 'Income'
                                        ? Colors.green
                                        : Colors.red)),
                            if (balances != null &&
                                balances.containsKey(category))
                              Text(
                                  'Balance: $currency ${balances[category]!.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      color: balances[category]! >= 0
                                          ? Colors.blue
                                          : Colors.orange)),
                          ],
                        ),
                        leading: Semantics(
                          label: type == 'Income'
                              ? 'Income category'
                              : 'Expense category',
                          child: Tooltip(
                            message: type == 'Income'
                                ? 'Income category'
                                : 'Expense category',
                            child: CircleAvatar(
                              backgroundColor:
                                  type == 'Income' ? Colors.green : Colors.red,
                              child: Icon(
                                type == 'Income'
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        children: transactions.map((transaction) {
                          currentCount++;
                          if (currentCount <= startIndex ||
                              currentCount > startIndex + _itemsPerPage) {
                            return const SizedBox.shrink();
                          }

                          return _buildTransactionTile(
                              transaction, currency, userId);
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
              _buildPagination(totalPages, type),
            ],
          );
  }

  Widget _buildEnhancedExpenseTab(
      {required Map<String, List<QueryDocumentSnapshot>> groupedTransactions,
      required String currency,
      required String userId,
      required Map<String, double> balances,
      required Map<String, double> allocatedAmounts}) {
    final filteredGroups = groupedTransactions.entries
        .where((entry) =>
            entry.key.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    final allCategories = groupedTransactions.keys.toList();
    final displayGroups = allCategories
        .where((category) =>
            category.toLowerCase().contains(_searchQuery.toLowerCase()))
        .map((category) => MapEntry(category,
            groupedTransactions[category] ?? <QueryDocumentSnapshot>[]))
        .toList();

    final totalItems =
        displayGroups.fold<int>(0, (sum, entry) => sum + entry.value.length);
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final currentTabPage = _tabPageNumbers['Expense'] ?? 0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          MediaQuery.of(context).size.width < 600 ? 2 : 3,
                      childAspectRatio:
                          MediaQuery.of(context).size.width < 400 ? 1.2 : 1.5,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: displayGroups.length,
                    itemBuilder: (context, index) {
                      final category = displayGroups[index].key;
                      final transactions = displayGroups[index].value;
                      final categoryTotal = transactions.fold<double>(0.0,
                          (sum, t) => sum + (t['amount'] as double? ?? 0.0));
                      final allocated = allocatedAmounts[category] ?? 0.0;
                      final balance = balances[category] ?? allocated;

                      return Card(
                        elevation: 2,
                        child: InkWell(
                          onTap: () => _showCategoryDetails(context, category,
                              transactions, currency, userId),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        category,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: balance >= 0
                                            ? Colors.green.withOpacity(0.1)
                                            : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$currency ${balance.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: balance >= 0
                                              ? Colors.green
                                              : Colors.red,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Spent',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 10,
                                          ),
                                        ),
                                        Text(
                                          '$currency ${categoryTotal.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'Received',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 10,
                                          ),
                                        ),
                                        Text(
                                          '$currency ${allocated.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: Colors.blue,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Text(
                                    'Balance: $currency ${balance.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: balance >= 0
                                            ? Colors.green
                                            : Colors.orange,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredGroups.length,
                  itemBuilder: (context, index) {
                    final category = filteredGroups[index].key;
                    final transactions = filteredGroups[index].value;
                    final startIndex = currentTabPage * _itemsPerPage;
                    final endIndex =
                        (startIndex + _itemsPerPage) > transactions.length
                            ? transactions.length
                            : startIndex + _itemsPerPage;

                    return ExpansionTile(
                      title: Text(category,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      children: transactions
                          .sublist(
                              startIndex > transactions.length ? 0 : startIndex,
                              endIndex)
                          .map((transaction) => _buildTransactionTile(
                              transaction, currency, userId))
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        _buildPagination(totalPages, 'Expense'),
      ],
    );
  }

  void _showCategoryDetails(
      BuildContext context,
      String category,
      List<QueryDocumentSnapshot> transactions,
      String currency,
      String userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$category Details'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: transactions.length,
            itemBuilder: (context, index) =>
                _buildTransactionTile(transactions[index], currency, userId),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
      QueryDocumentSnapshot transaction, String currency, String userId) {
    final transactionId = transaction.id;
    final description =
        transaction['description'] as String? ?? 'No description';
    final amount = transaction['amount'] as double? ?? 0.0;
    final date = transaction['date'] as String? ?? 'No date';
    final rawSms = transaction['rawSms'] as String? ?? 'No SMS data';
    final type = transaction['type'] as String? ?? 'Unknown';
    final categoryId = transaction['categoryId'] as String? ?? 'Unknown';

    String formattedDate;
    try {
      final dateTime = DateTime.parse(date);
      formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
    } catch (e) {
      formattedDate = 'Invalid Date';
      log('Failed to parse date "$date": $e');
    }

    return TransactionTile(
      type: type,
      description: description,
      categoryId: categoryId,
      date: formattedDate,
      amount: amount,
      currency: currency,
      rawSms: rawSms,
      onTap: () => _showTransactionDetails(
          context,
          {
            'amount': amount,
            'date': date,
            'description': description,
            'rawSms': rawSms,
            'currency': currency,
            'transactionId': transactionId,
            'type': type,
            'categoryId': categoryId,
          },
          userId),
    );
  }

  Widget _buildAllocationsTab(
      Map<String, List<Map<String, dynamic>>> groupedAllocations,
      String currency,
      String userId) {
    final filteredGroups = groupedAllocations.entries
        .where((entry) => entry.value.any((alloc) => alloc['categoryId']
            .toLowerCase()
            .contains(_searchQuery.toLowerCase())))
        .toList();
    final currentTabPage = _tabPageNumbers['Allocations'] ?? 0;
    final startIndex = currentTabPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage) > filteredGroups.length
        ? filteredGroups.length
        : startIndex + _itemsPerPage;
    final currentGroups = filteredGroups.sublist(startIndex, endIndex);
    final totalPages = (filteredGroups.length / _itemsPerPage).ceil();

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: currentGroups.length,
            itemBuilder: (context, index) {
              final group = currentGroups[index];
              final transactionId = group.key;
              final allocations = group.value;
              final totalAllocated = allocations.fold<double>(
                  0.0, (sum, alloc) => sum + alloc['amount']);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: ExpansionTile(
                  title: Text(
                      'Transaction ID: ${transactionId.substring(0, 8)}...'),
                  subtitle: Text(
                      'Total: $currency ${totalAllocated.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.blue)),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.account_balance,
                        color: Colors.white, size: 16),
                  ),
                  children: allocations.map((allocation) {
                    final allocationId = allocation['id'];
                    final category = allocation['categoryId'];
                    final amount = allocation['amount'] as double;
                    final timestamp = allocation['timestamp'] as DateTime;
                    final formattedDate =
                        DateFormat('dd/MM/yyyy HH:mm').format(timestamp);

                    return ListTile(
                      title: Text(category),
                      subtitle: Text(
                          '$currency ${amount.toStringAsFixed(2)} • $formattedDate'),
                      trailing: Tooltip(
                        message: 'Delete allocation',
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              _deleteAllocation(allocationId, userId),
                          tooltip: 'Delete allocation',
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
        _buildPagination(totalPages, 'Allocations'),
      ],
    );
  }

  Widget _buildMasterExpenseTab(List<QueryDocumentSnapshot> transactions,
      String currency, String userId) {
    final filteredTransactions = transactions.where((t) {
      final category = t['categoryId'] as String?;
      final type = t['type'] as String? ?? '';
      final dateStr = t['date'] as String? ?? '';

      bool matchesSearch = category != null &&
          category.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          type == 'Expense';

      if (_selectedMasterExpenseDate != null && matchesSearch) {
        try {
          final transactionDate = DateTime.parse(dateStr);
          return transactionDate.year == _selectedMasterExpenseDate!.year &&
              transactionDate.month == _selectedMasterExpenseDate!.month &&
              transactionDate.day == _selectedMasterExpenseDate!.day;
        } catch (e) {
          log('Failed to parse date "$dateStr": $e');
          return false;
        }
      }
      return matchesSearch;
    }).toList()
      ..sort((a, b) {
        try {
          final dateA = DateTime.parse(a['date'] as String? ?? '');
          final dateB = DateTime.parse(b['date'] as String? ?? '');
          return dateB.compareTo(dateA); // Most recent first
        } catch (e) {
          return 0; // Keep original order if date parsing fails
        }
      });

    final totalPages = (filteredTransactions.length / _itemsPerPage).ceil();
    final currentTabPage = _tabPageNumbers['Master Expenses'] ?? 0;
    final startIndex = currentTabPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage) > filteredTransactions.length
        ? filteredTransactions.length
        : startIndex + _itemsPerPage;
    final currentTransactions =
        filteredTransactions.sublist(startIndex, endIndex);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedMasterExpenseDate != null
                    ? 'Date: ${DateFormat('dd/MM/yyyy').format(_selectedMasterExpenseDate!)}'
                    : 'All Dates',
                style: const TextStyle(fontSize: 16),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pickDate(context, 'Master Expenses'),
                    tooltip: 'Select Date',
                  ),
                  if (_selectedMasterExpenseDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _selectedMasterExpenseDate = null;
                          _tabPageNumbers['Master Expenses'] = 0;
                        });
                      },
                      tooltip: 'Clear Date Filter',
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: currentTransactions.isEmpty
              ? Center(
                  child: Text(
                      _selectedMasterExpenseDate != null
                          ? 'No expenses found for ${DateFormat('dd/MM/yyyy').format(_selectedMasterExpenseDate!)}'
                          : 'No expenses found',
                      style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: currentTransactions.length,
                  itemBuilder: (context, index) {
                    final transaction = currentTransactions[index];
                    final amount = transaction['amount'] as double? ?? 0.0;
                    final date = transaction['date'] as String? ?? 'No date';
                    final categoryId =
                        transaction['categoryId'] as String? ?? '';
                    final description = transaction['description'] as String? ??
                        'No description';

                    String formattedDate;
                    try {
                      final dateTime = DateTime.parse(date);
                      formattedDate =
                          DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
                    } catch (e) {
                      formattedDate = 'Invalid Date';
                      log('Failed to parse date "$date": $e');
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(description),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Category: $categoryId'),
                            Text('Date: $formattedDate'),
                            Text(
                                'Amount: $currency ${amount.toStringAsFixed(2)}'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.undo, color: Colors.orange),
                              tooltip: 'Reverse Categorization',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Reverse Categorization'),
                                    content: const Text(
                                        'Are you sure you want to reverse this transaction?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Reverse',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                try {
                                  // Set categoryId to 'Uncategorized'
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(userId)
                                      .collection('transactions')
                                      .doc(transaction.id)
                                      .update({'categoryId': 'Uncategorized'});
                                  // Remove allocations for this transaction
                                  final allocs = await FirebaseFirestore
                                      .instance
                                      .collection('users')
                                      .doc(userId)
                                      .collection('allocations')
                                      .where('transactionId',
                                          isEqualTo: transaction.id)
                                      .get();
                                  for (var doc in allocs.docs) {
                                    await doc.reference.delete();
                                  }
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Transaction reversed.')),
                                    );
                                    setState(() {});
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text('Failed to reverse: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        _buildPagination(totalPages, 'Master Expenses'),
      ],
    );
  }

  Widget _buildMasterIncomeTab(List<QueryDocumentSnapshot> transactions,
      String currency, String userId) {
    final filteredTransactions = transactions.where((t) {
      final category = t['categoryId'] as String?;
      final type = t['type'] as String? ?? '';
      final dateStr = t['date'] as String? ?? '';

      bool matchesSearch = category != null &&
          category.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          type == 'Income';

      if (_selectedMasterIncomeDate != null && matchesSearch) {
        try {
          final transactionDate = DateTime.parse(dateStr);
          return transactionDate.year == _selectedMasterIncomeDate!.year &&
              transactionDate.month == _selectedMasterIncomeDate!.month &&
              transactionDate.day == _selectedMasterIncomeDate!.day;
        } catch (e) {
          log('Failed to parse date "$dateStr": $e');
          return false;
        }
      }
      return matchesSearch;
    }).toList()
      ..sort((a, b) {
        try {
          final dateA = DateTime.parse(a['date'] as String? ?? '');
          final dateB = DateTime.parse(b['date'] as String? ?? '');
          return dateB.compareTo(dateA); // Most recent first
        } catch (e) {
          return 0; // Keep original order if date parsing fails
        }
      });

    final totalPages = (filteredTransactions.length / _itemsPerPage).ceil();
    final currentTabPage = _tabPageNumbers['Master Income'] ?? 0;
    final startIndex = currentTabPage * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage) > filteredTransactions.length
        ? filteredTransactions.length
        : startIndex + _itemsPerPage;
    final currentTransactions =
        filteredTransactions.sublist(startIndex, endIndex);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedMasterIncomeDate != null
                    ? 'Date: ${DateFormat('dd/MM/yyyy').format(_selectedMasterIncomeDate!)}'
                    : 'All Dates',
                style: const TextStyle(fontSize: 16),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pickDate(context, 'Master Income'),
                    tooltip: 'Select Date',
                  ),
                  if (_selectedMasterIncomeDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _selectedMasterIncomeDate = null;
                          _tabPageNumbers['Master Income'] = 0;
                        });
                      },
                      tooltip: 'Clear Date Filter',
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: currentTransactions.isEmpty
              ? Center(
                  child: Text(
                      _selectedMasterIncomeDate != null
                          ? 'No income found for ${DateFormat('dd/MM/yyyy').format(_selectedMasterIncomeDate!)}'
                          : 'No income found',
                      style: const TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: currentTransactions.length,
                  itemBuilder: (context, index) {
                    final transaction = currentTransactions[index];
                    final amount = transaction['amount'] as double? ?? 0.0;
                    final date = transaction['date'] as String? ?? 'No date';
                    final categoryId =
                        transaction['categoryId'] as String? ?? '';
                    final description = transaction['description'] as String? ??
                        'No description';

                    String formattedDate;
                    try {
                      final dateTime = DateTime.parse(date);
                      formattedDate =
                          DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
                    } catch (e) {
                      formattedDate = 'Invalid Date';
                      log('Failed to parse date "$date": $e');
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: TransactionTile(
                        type: 'Income',
                        description: description,
                        categoryId: categoryId,
                        date: formattedDate,
                        amount: amount,
                        currency: currency,
                        rawSms:
                            transaction['rawSms'] as String? ?? 'No SMS data',
                        leading: Semantics(
                          label: 'Income transaction',
                          child: Tooltip(
                            message: 'Income transaction',
                            child: CircleAvatar(
                              backgroundColor: Colors.green[100],
                              child: const Icon(Icons.arrow_downward,
                                  color: Colors.green, size: 16),
                            ),
                          ),
                        ),
                        amountColor: Colors.green,
                        onTap: () => _showTransactionDetails(
                          context,
                          {
                            'amount': amount,
                            'date': date,
                            'description': description,
                            'rawSms': transaction['rawSms'] as String? ??
                                'No SMS data',
                            'currency': currency,
                            'transactionId': transaction.id,
                            'type': transaction['type'] as String? ?? 'Income',
                          },
                          userId,
                        ),
                      ),
                    );
                  },
                ),
        ),
        _buildPagination(totalPages, 'Master Income'),
      ],
    );
  }

  Widget _buildPagination(int totalPages, String tabKey) {
    final currentTabPage = _tabPageNumbers[tabKey] ?? 0;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: currentTabPage > 0
                ? () =>
                    setState(() => _tabPageNumbers[tabKey] = currentTabPage - 1)
                : null,
            tooltip: 'Previous page',
          ),
          Text('Page ${currentTabPage + 1} of $totalPages'),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: currentTabPage < totalPages - 1
                ? () =>
                    setState(() => _tabPageNumbers[tabKey] = currentTabPage + 1)
                : null,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  final String type;
  final String description;
  final String categoryId;
  final String date;
  final double amount;
  final String currency;
  final String rawSms;
  final Widget? leading;
  final Color? amountColor;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.type,
    required this.description,
    required this.categoryId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.rawSms,
    this.leading,
    this.amountColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Minimum tap target size for accessibility
    return Semantics(
      label:
          '$type transaction: $description, category $categoryId, amount $currency ${amount.toStringAsFixed(2)}, date $date',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints:
                const BoxConstraints(minHeight: 56, minWidth: double.infinity),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                leading ??
                    CircleAvatar(
                      backgroundColor: type == 'Income'
                          ? Colors.green[100]
                          : Colors.red[100],
                      child: Icon(
                        type == 'Income'
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        color: type == 'Income' ? Colors.green : Colors.red,
                        size: 18,
                      ),
                    ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        description,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        semanticsLabel: 'Description: $description',
                      ),
                      Text(
                        'Category: $categoryId',
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        semanticsLabel: 'Category: $categoryId',
                      ),
                      Text(
                        date,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                        semanticsLabel: 'Date: $date',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Text(
                    '$currency ${amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: amountColor ??
                          (type == 'Income' ? Colors.green : Colors.red),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                // Add a visually hidden button for screen readers to access details
                Semantics(
                  label: 'Show details for this transaction',
                  button: true,
                  child: const SizedBox(width: 0, height: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
