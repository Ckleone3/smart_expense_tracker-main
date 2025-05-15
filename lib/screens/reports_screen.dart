import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:developer';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  // Fetch all income categories
  Future<List<String>> _fetchIncomeCategories(String userId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: 'Income')
        .get();
    return snapshot.docs.map((doc) => doc['name'] as String).toList();
  }

  // Fetch allocations for expense balances
  Future<Map<String, double>> _fetchAllocations(String userId) async {
    final allocationsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('allocations')
        .get();

    final Map<String, double> allocatedAmounts = {};
    for (var doc in allocationsSnapshot.docs) {
      final categoryId = doc['categoryId'] as String;
      final amount = (doc['amount'] as num?)?.toDouble() ?? 0.0;
      allocatedAmounts[categoryId] = (allocatedAmounts[categoryId] ?? 0.0) + amount;
    }
    return allocatedAmounts;
  }

  // Fetch user's preferred currency
  Future<String> _fetchCurrency(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('currency')
        .get();
    return doc.exists ? (doc['currency'] as String? ?? 'USD') : 'USD';
  }

  // Predefined color palette for expense categories (pie chart)
  static const List<Color> expenseColors = [
    Color(0xFF2196F3), // Blue
    Color(0xFFF44336), // Red
    Color(0xFF4CAF50), // Green
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFF00BCD4), // Cyan
    Color(0xFFE91E63), // Pink
    Color(0xFF8BC34A), // Light Green
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF673AB7), // Deep Purple
  ];

  // Colors for bar chart
  static const Color incomeColor = Color(0xFF4CAF50); // Green
  static const Color expenseColor = Color(0xFFF44336); // Red

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    log('ReportsScreen: User ID = $userId');

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: const Center(child: Text('Please sign in to view reports')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 24),
            SizedBox(width: 8),
            Text('Financial Reports'),
          ],
        ),
        centerTitle: true,
        elevation: 2,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('transactions')
            .where('categoryId', isNotEqualTo: null)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, transactionSnapshot) {
          if (transactionSnapshot.hasError) {
            log('Transaction query error: ${transactionSnapshot.error}');
            return Center(child: Text('Error: ${transactionSnapshot.error}'));
          }

          if (!transactionSnapshot.hasData) {
            log('Loading transactions...');
            return const Center(child: CircularProgressIndicator());
          }

          final transactions = transactionSnapshot.data!.docs;
          return FutureBuilder<Map<String, dynamic>>(
            future: Future.wait([
              _fetchIncomeCategories(userId),
              _fetchAllocations(userId),
              _fetchCurrency(userId),
            ]).then((results) => {
                  'incomeCategories': results[0] as List<String>,
                  'allocations': results[1] as Map<String, double>,
                  'currency': results[2] as String,
                }),
            builder: (context, futureSnapshot) {
              if (futureSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (futureSnapshot.hasError) {
                log('Future fetch error: ${futureSnapshot.error}');
                return Center(child: Text('Error: ${futureSnapshot.error}'));
              }

              final incomeCategories = futureSnapshot.data!['incomeCategories'] as List<String>;
              final allocatedAmounts = futureSnapshot.data!['allocations'] as Map<String, double>;
              final currency = futureSnapshot.data!['currency'] as String;
              final filteredTransactions = transactions.where((t) => t['categoryId'] != null).toList();

              if (filteredTransactions.isEmpty && incomeCategories.isEmpty) {
                return const Center(child: Text('No data available for reports'));
              }

              // Process data
              final Map<String, Map<String, double>> groupedTotals = {
                'Income': {},
                'Expense': {},
              };
              double totalIncome = 0.0;
              double totalExpense = 0.0;
              final Map<String, double> expenseTotals = {};

              // Initialize income categories
              for (var category in incomeCategories) {
                groupedTotals['Income']![category] = 0.0;
              }

              for (var transaction in filteredTransactions) {
                final type = transaction['type'] as String? ?? 'Unknown';
                final category = transaction['categoryId'] as String;
                final amount = transaction['amount'] as double? ?? 0.0;

                if (type == 'Income') {
                  totalIncome += amount;
                  groupedTotals['Income']![category] = (groupedTotals['Income']![category] ?? 0.0) + amount;
                } else if (type == 'Expense') {
                  totalExpense += amount;
                  groupedTotals['Expense']![category] = (groupedTotals['Expense']![category] ?? 0.0) + amount;
                  expenseTotals[category] = (expenseTotals[category] ?? 0.0) + amount;
                }
              }

              // Calculate balances
              final Map<String, double> balances = {};
              expenseTotals.forEach((category, spent) {
                final allocated = allocatedAmounts[category] ?? 0.0;
                balances[category] = allocated - spent;
              });

              // Build UI
              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Financial Statement
                      Container(
                        margin: const EdgeInsets.only(top: 16, bottom: 8),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Financial Statement',
                              style: TextStyle(
                                fontSize: 20, 
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Total Income: $currency ${totalIncome.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.green,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.arrow_upward, color: Colors.red, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Total Expenses: $currency ${totalExpense.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12.0),
                                child: Divider(),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.calculate, color: Colors.purple, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Net Balance: $currency ${(totalIncome - totalExpense).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16, 
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.account_balance_wallet, color: Colors.blue, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Available Balance: $currency ${balances.values.fold<double>(0.0, (sum, b) => sum + b).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.blue,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Pie Chart for Expense Distribution
                      if (groupedTotals['Expense']!.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.only(top: 16, bottom: 8),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.pie_chart, color: Colors.red),
                              SizedBox(width: 8),
                              Text(
                                'Expense Distribution',
                                style: TextStyle(
                                  fontSize: 20, 
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 200,
                          child: PieChart(
                            PieChartData(
                              sections: groupedTotals['Expense']!.entries.toList().asMap().entries.map((entry) {
                                final index = entry.key;
                                final category = entry.value.key;
                                final value = entry.value.value;
                                final percentage = (value / totalExpense) * 100;
                                return PieChartSectionData(
                                  value: value,
                                  title: '${percentage.toStringAsFixed(1)}%',
                                  radius: 50,
                                  color: expenseColors[index % expenseColors.length],
                                  titleStyle: const TextStyle(fontSize: 12, color: Colors.white),
                                );
                              }).toList(),
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: groupedTotals['Expense']!.keys.toList().asMap().entries.map((entry) {
                            final index = entry.key;
                            final category = entry.value;
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: expenseColors[index % expenseColors.length],
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(category, style: const TextStyle(fontSize: 14)),
                              ],
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Bar Chart for Income vs Expenses by Category
                      const Text(
                        'Income vs Expenses by Category',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 300,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            barGroups: _buildBarGroups(groupedTotals, incomeCategories, totalIncome, totalExpense),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final allCategories = [
                                      ...incomeCategories,
                                      ...groupedTotals['Expense']!.keys.toSet().difference(incomeCategories.toSet())
                                    ];
                                    final index = value.toInt();
                                    if (index >= 0 && index < allCategories.length) {
                                      return SideTitleWidget(
                                        space: 8.0,
                                        meta: meta,
                                        child: Text(
                                          allCategories[index],
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                  reservedSize: 40,
                                ),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(show: false),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: incomeColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Income', style: TextStyle(fontSize: 14)),
                          const SizedBox(width: 20),
                          Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: expenseColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('Expenses', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Helper to build bar groups for bar chart with improved colors
  List<BarChartGroupData> _buildBarGroups(
      Map<String, Map<String, double>> groupedTotals,
      List<String> incomeCategories,
      double totalIncome, // Added parameter
      double totalExpense // Added parameter
      ) {
    final allCategories = <dynamic>{
      ...incomeCategories,
      ...groupedTotals['Expense']!.keys.toSet().difference(incomeCategories.toSet())
    }.toList();

    return allCategories.asMap().entries.map((entry) {
      final index = entry.key;
      final category = entry.value;
      final income = groupedTotals['Income']![category] ?? 0.0;
      final expense = groupedTotals['Expense']![category] ?? 0.0;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: income,
            color: incomeColor,
            width: 16,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: totalIncome * 1.1, // Now accessible
              color: incomeColor.withOpacity(0.1),
            ),
          ),
          BarChartRodData(
            toY: expense,
            color: expenseColor,
            width: 16,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: totalExpense * 1.1, // Now accessible
              color: expenseColor.withOpacity(0.1),
            ),
          ),
        ],
        showingTooltipIndicators: [0, 1],
      );
    }).toList();
  }
}
