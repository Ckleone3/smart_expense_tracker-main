import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'categorized_screen.dart';
import 'reports_screen.dart';
import 'uncategorized_screen.dart';
import 'settings_screen.dart';
import 'ledger_screen.dart';

class DashboardScreen extends StatefulWidget {
  /// Global actions surfaced on the Home app bar (handlers live in HomeScreen).
  final VoidCallback? onAddCash;
  final VoidCallback? onFetchSms;
  final VoidCallback? onLogout;

  const DashboardScreen({
    super.key,
    this.onAddCash,
    this.onFetchSms,
    this.onLogout,
  });

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

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to use the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) widget.onLogout?.call();
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
    final balance = totalIncome - totalExpense;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                _buildSliverAppBar(),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildHeroBalanceCard(balance),
                      const SizedBox(height: 24),
                      _buildIncomeExpenseRow(),
                      const SizedBox(height: 24),
                      if (totalIncome > 0 || totalExpense > 0) ...[
                        _buildChartSection(),
                        const SizedBox(height: 32),
                      ],
                      const Text(
                        'Quick Navigation',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 16),
                      _buildQuickNavGrid(),
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF3F51B5), // Primary color
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        title: const Text(
          'Good morning!',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          tooltip: 'More',
          onSelected: (v) {
            switch (v) {
              case 'add':
                widget.onAddCash?.call();
                break;
              case 'fetch':
                widget.onFetchSms?.call();
                break;
              case 'settings':
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                break;
              case 'logout':
                _confirmLogout();
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'add',
              child: ListTile(
                  leading: Icon(Icons.add, color: Colors.green),
                  title: Text('Add cash')),
            ),
            PopupMenuItem(
              value: 'fetch',
              child: ListTile(
                  leading: Icon(Icons.sms, color: Colors.blue),
                  title: Text('Fetch SMS by date')),
            ),
            PopupMenuItem(
              value: 'settings',
              child: ListTile(
                  leading: Icon(Icons.settings, color: Colors.grey),
                  title: Text('Settings')),
            ),
            PopupMenuItem(
              value: 'logout',
              child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
                  title: Text('Logout')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroBalanceCard(double balance) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white70,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Total Balance',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '$currency ${NumberFormat('#,##0.00', 'en_US').format(balance)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeExpenseRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Income',
            amount: totalIncome,
            icon: Icons.arrow_downward_rounded,
            color: const Color(0xFF10B981), // Emerald green
            bgColor: Colors.white,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildMetricCard(
            title: 'Expenses',
            amount: totalExpense,
            icon: Icons.arrow_upward_rounded,
            color: const Color(0xFFEF4444), // Red
            bgColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF64748B), // Slate 500
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$currency ${NumberFormat('#,##0.00', 'en_US').format(amount)}',
            style: const TextStyle(
              color: Color(0xFF1E293B), // Slate 800
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    final double incomePercentage =
        totalIncome / ((totalIncome + totalExpense) == 0 ? 1 : (totalIncome + totalExpense));
    final double expensePercentage =
        totalExpense / ((totalIncome + totalExpense) == 0 ? 1 : (totalIncome + totalExpense));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 50,
                sections: [
                  if (totalIncome > 0)
                    PieChartSectionData(
                      color: const Color(0xFF10B981),
                      value: totalIncome,
                      title: '${(incomePercentage * 100).toStringAsFixed(0)}%',
                      radius: 20,
                      titleStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  if (totalExpense > 0)
                    PieChartSectionData(
                      color: const Color(0xFFEF4444),
                      value: totalExpense,
                      title: '${(expensePercentage * 100).toStringAsFixed(0)}%',
                      radius: 20,
                      titleStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildChartLegend(color: const Color(0xFF10B981), text: 'Income'),
              const SizedBox(width: 24),
              _buildChartLegend(color: const Color(0xFFEF4444), text: 'Expense'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildChartLegend({required Color color, required String text}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        )
      ],
    );
  }

  Widget _buildQuickNavGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildGridNavButton(
                icon: Icons.list_alt,
                label: 'Uncategorized',
                color: const Color(0xFFF59E0B), // Amber
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UncategorizedScreen()),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildGridNavButton(
                icon: Icons.category,
                label: 'Categorized',
                color: const Color(0xFF6366F1), // Indigo
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CategorizedScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildGridNavButton(
                icon: Icons.bar_chart,
                label: 'Reports',
                color: const Color(0xFF06B6D4), // Cyan
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildGridNavButton(
                icon: Icons.menu_book,
                label: 'Ledger',
                color: const Color(0xFF10B981), // Emerald green
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LedgerScreen()),
                ),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildGridNavButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
