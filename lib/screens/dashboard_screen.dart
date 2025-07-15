import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'categorized_screen.dart';
import 'reports_screen.dart';
import 'uncategorized_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  double totalIncome = 0.0;
  double totalExpense = 0.0;
  String currency = 'Ksh';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSummaryData();
  }

  Future<void> _fetchSummaryData() async {
    if (!mounted) return;

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() => isLoading = false);
      return;
    }

    try {
      // Fetch currency
      final settingsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('currency')
          .get();
      if (!mounted) return;
      currency = settingsDoc.exists
          ? (settingsDoc['currency'] as String? ?? 'Ksh')
          : 'Ksh';

      // Try to fetch summary document first
      final summaryDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('summary')
          .doc('totals')
          .get();
      if (summaryDoc.exists) {
        totalIncome = (summaryDoc['totalIncome'] as num?)?.toDouble() ?? 0.0;
        totalExpense = (summaryDoc['totalExpense'] as num?)?.toDouble() ?? 0.0;
        // Optionally, you can fetch balances if you want to show per-category
        setState(() => isLoading = false);
        return;
      }

      // If summary is missing, fallback to full calculation (legacy)
      final txSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('transactions')
          .where('categoryId', isNotEqualTo: null)
          .where('categoryId', isNotEqualTo: 'Uncategorized')
          .get();

      double inc = 0.0;
      double exp = 0.0;
      final expenseTotals = <String, double>{};
      final allocatedAmounts = <String, double>{};

      final allocationsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('allocations')
          .orderBy('timestamp', descending: true)
          .get();
      for (var doc in allocationsSnapshot.docs) {
        final categoryId = doc['categoryId'] as String;
        final amount = (doc['amount'] as num?)?.toDouble() ?? 0.0;
        allocatedAmounts[categoryId] =
            (allocatedAmounts[categoryId] ?? 0.0) + amount;
      }
      for (var doc in txSnapshot.docs) {
        final type = doc['type'] as String? ?? '';
        final category = doc['categoryId'] as String?;
        final amount = (doc['amount'] as num?)?.toDouble() ?? 0.0;
        if (category != null) {
          if (type == 'Income') {
            inc += amount;
          } else if (type == 'Expense') {
            exp += amount;
            expenseTotals[category] = (expenseTotals[category] ?? 0.0) + amount;
          }
        }
      }
      final balances = expenseTotals.map((category, spent) =>
          MapEntry(category, (allocatedAmounts[category] ?? 0.0) - spent));
      totalIncome = inc;
      totalExpense = exp;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('summary')
          .doc('totals')
          .set({
        'totalIncome': inc,
        'totalExpense': exp,
        'categoryBalances': balances,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      log('Error fetching summary data: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        titleTextStyle: const TextStyle(
            color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
      ),
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        bottom: true,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  bottomInset + 32, // increased bottom padding for nav bar
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Financial Summary',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222B45)),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _summaryCard(
                            'Total Income',
                            '$currency ${totalIncome.toStringAsFixed(2)}',
                            Icons.arrow_downward,
                            const Color(0xFF4CAF50),
                            const Color(0xFFE8F5E9),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _summaryCard(
                            'Total Expenses',
                            '$currency ${totalExpense.toStringAsFixed(2)}',
                            Icons.arrow_upward,
                            const Color(0xFFF44336),
                            const Color(0xFFFFEBEE),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _summaryCard(
                      'Balance',
                      '$currency ${(totalIncome - totalExpense).toStringAsFixed(2)}',
                      Icons.account_balance_wallet,
                      (totalIncome - totalExpense) >= 0
                          ? const Color(0xFF1976D2)
                          : const Color(0xFFFF9800),
                      (totalIncome - totalExpense) >= 0
                          ? const Color(0xFFE3F2FD)
                          : const Color(0xFFFFF3E0),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Quick Navigation',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222B45)),
                    ),
                    const SizedBox(height: 16),
                    _dashboardNavButton(
                      icon: Icons.list_alt,
                      label: 'Uncategorized',
                      color: const Color(0xFFFFC107),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const UncategorizedScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dashboardNavButton(
                      icon: Icons.category,
                      label: 'Categorized',
                      color: const Color(0xFF7C4DFF),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CategorizedScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dashboardNavButton(
                      icon: Icons.bar_chart,
                      label: 'Reports',
                      color: const Color(0xFF00BFAE),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summaryCard(
      String title, String value, IconData icon, Color color, Color bgColor) {
    return Card(
      color: bgColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.12),
              radius: 22,
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardNavButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios,
                      size: 18, color: color.withOpacity(0.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
