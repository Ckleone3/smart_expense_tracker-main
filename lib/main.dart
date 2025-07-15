import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:smart_expense_tracker/services/subscription_service.dart';
import 'package:smart_expense_tracker/services/sms_service.dart';
import 'package:smart_expense_tracker/screens/auth_screens.dart';
import 'package:smart_expense_tracker/screens/categorized_screen.dart';
import 'package:smart_expense_tracker/screens/uncategorized_screen.dart';
import 'package:smart_expense_tracker/screens/reports_screen.dart';
import 'package:smart_expense_tracker/screens/settings_screen.dart';
import 'package:smart_expense_tracker/screens/tutorial_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:smart_expense_tracker/widgets/custom_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:smart_expense_tracker/screens/dashboard_screen.dart';

import 'firebase_options.dart';
import 'services/storage/storage_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  runZonedGuarded<Future<void>>(() async {
    runApp(const MyApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SubscriptionService>(
          create: (_) => SubscriptionService(),
        ),
        Provider<SmsService>(
          create: (context) => SmsService(
            subscriptionService: context.read<SubscriptionService>(),
          ),
        ),
        ChangeNotifierProvider<StorageService>(
          create: (context) => StorageService(
            subscriptionService: context.read<SubscriptionService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Smart Expense Tracker',
        theme: AppTheme.theme,
        themeMode: ThemeMode.system,
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasData) {
              return const HomeScreen();
            }
            return const WelcomeScreen();
          },
        ),
        routes: {
          '/tutorial': (context) => const TutorialScreen(),
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late SmsService _smsService;

  static final List<Widget> _screens = [
    const DashboardScreen(),
    const UncategorizedScreen(),
    const CategorizedScreen(),
    const ReportsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _smsService = Provider.of<SmsService>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

      if (!hasSeenOnboarding) {
        await prefs.setBool('hasSeenOnboarding', true);

        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TutorialScreen()),
        );

        final startTrial = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Try Premium free for 7 days?'),
            content: const Text(
              'Get cloud sync, cross-device access, and advanced reports for 7 days.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('No, thanks'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Start Trial'),
              ),
            ],
          ),
        );

        if (startTrial == true) {
          await prefs.setString(
            'trial_start',
            DateTime.now().toIso8601String(),
          );
          await context.read<SubscriptionService>().upgradeToPremium();
        }
      }

      // After your existing onboarding/trial prompt block:

// --- TRIAL EXPIRATION CHECK ---
      final trialStr = prefs.getString('trial_start');
      if (trialStr != null) {
        final start = DateTime.parse(trialStr);
        final elapsed = DateTime.now().difference(start);
        if (elapsed >= const Duration(days: 7)) {
          // Trial has ended!
          await context.read<SubscriptionService>().downgradeToFree();
          await prefs.remove('trial_start');
          // Let the user know
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Trial Ended'),
              content: const Text(
                'Your 7-day Premium trial has ended. You’re now on the Free plan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                )
              ],
            ),
          );
        }
      }

      _initializeServiceAndSync();
    });
  }

  @override
  void dispose() {
    _smsService.dispose();
    super.dispose();
  }

  Future<void> _initializeServiceAndSync() async {
    try {
      await _smsService.init();
      final newMessages = await _smsService.initializeSmsStore();
      if (newMessages > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stored $newMessages new SMS messages')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during initial SMS sync: $e')),
      );
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  void _handleLogout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  void _showFetchOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fetch SMS Transactions'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _buildDialogButton(
                context: context,
                icon: Icons.calendar_today,
                label: 'Select Day',
                onPressed: () async {
                  final selectedDate = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (selectedDate != null) {
                    Navigator.pop(context);
                    _fetchSms('day', selectedDate);
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildDialogButton(
                context: context,
                icon: Icons.date_range,
                label: 'Select Date Range',
                onPressed: () async {
                  final startDate = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.now().subtract(const Duration(days: 7)),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (startDate != null) {
                    final endDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: startDate,
                      lastDate: DateTime.now(),
                    );
                    if (endDate != null) {
                      Navigator.pop(context);
                      _fetchSms('range', startDate, rangeEnd: endDate);
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              _buildDialogButton(
                context: context,
                icon: Icons.calendar_month,
                label: 'Select Month',
                onPressed: () => _showMonthYearPicker(context),
              ),
            ],
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

  ElevatedButton _buildDialogButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 20),
      label: Text(label),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  void _showMonthYearPicker(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(currentYear - 2019, (i) => currentYear - i);
    final months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    int? selectedYear = currentYear;
    int? selectedMonth = DateTime.now().month;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Month and Year'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Year', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _yearDropdown(selectedYear, years, setState),
              const SizedBox(height: 16),
              const Text('Month',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _monthDropdown(selectedMonth, months, setState),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Fetch'),
              onPressed: () {
                final date = DateTime(selectedYear, selectedMonth, 1);
                Navigator.pop(context);
                _fetchSms('month', date);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _yearDropdown(
      int? selectedYear, List<int> years, StateSetter setState) {
    return DropdownButton<int>(
      value: selectedYear,
      isExpanded: true,
      underline: const SizedBox(),
      items: years
          .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
          .toList(),
      onChanged: (v) => setState(() => selectedYear = v),
    );
  }

  Widget _monthDropdown(
      int? selectedMonth, List<String> months, StateSetter setState) {
    return DropdownButton<int>(
      value: selectedMonth,
      isExpanded: true,
      underline: const SizedBox(),
      items: months
          .asMap()
          .entries
          .map((e) => DropdownMenuItem(value: e.key + 1, child: Text(e.value)))
          .toList(),
      onChanged: (v) => setState(() => selectedMonth = v),
    );
  }

  void _fetchSms(String fetchType, DateTime referenceDate,
      {DateTime? rangeEnd}) async {
    Navigator.pop(context);
    try {
      final result = await _smsService
          .fetchTransactions(fetchType, referenceDate, rangeEnd: rangeEnd);
      final parsed = result['parsed']!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(parsed > 0
                ? 'Retrieved $parsed SMS transactions from store'
                : 'No matching SMS transactions found for this date')),
      );
    } catch (e) {
      if (e.toString().contains('NO_KEYWORDS_AVAILABLE')) {
        _showNoKeywordsDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching transactions: $e')),
        );
      }
    }
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
                'To fetch SMS transactions, you need to set up keywords.'),
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
              child: const Text('Later')),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Go to Settings'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ],
      ),
    );
  }

  Future<List<String>> _fetchCategories(String type) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('categories')
        .where('type', isEqualTo: type)
        .get();
    return snap.docs.map((d) => d['name'] as String).toList();
  }

  Future<void> _allocateIncome(
      String txId, double amount, String userId) async {
    final expCats = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();
    for (var doc in expCats.docs) {
      final pct = (doc['percentage'] as num?)?.toDouble() ?? 0;
      final alloc = (amount * pct) / 100;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('allocations')
          .add({
        'transactionId': txId,
        'categoryId': doc['name'],
        'amount': alloc,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<double> _calculateExpensePercentageTotal() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 0;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();
    return snap.docs.fold<double>(
        0, (sum, d) => sum + ((d['percentage'] as num?)?.toDouble() ?? 0));
  }

  void _addManualTransaction(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to add transactions')),
      );
      return;
    }
    String? type;
    final amtCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selCat;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Cash Transaction'),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'Type', border: OutlineInputBorder()),
                  value: type,
                  items: ['Income', 'Expense']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      type = v;
                      selCat = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                    controller: amtCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Amount', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder())),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        'Date: ${DateFormat('dd/MM/yy').format(selectedDate)}'),
                    TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now());
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                        child: const Text('Pick Date')),
                  ],
                ),
                const SizedBox(height: 16),
                if (type != null)
                  FutureBuilder<List<String>>(
                    future: _fetchCategories(type!),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const CircularProgressIndicator();
                      }
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                            labelText: 'Category (Optional)',
                            border: OutlineInputBorder()),
                        value: selCat,
                        items: snap.data!
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (v) => setState(() => selCat = v),
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () async {
                  if (type == null ||
                      amtCtrl.text.isEmpty ||
                      descCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Please fill all required fields')));
                    return;
                  }
                  final amt = double.tryParse(amtCtrl.text);
                  if (amt == null || amt <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Please enter a valid amount')));
                    return;
                  }
                  if (type == 'Income') {
                    final total = await _calculateExpensePercentageTotal();
                    if (total != 100) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Expense categories must total 100% to allocate income.')));
                      return;
                    }
                  }

                  try {
                    final docRef = FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .collection('transactions')
                        .doc();
                    final data = {
                      'type': type,
                      'amount': amt,
                      'description': descCtrl.text,
                      'date': selectedDate.toIso8601String(),
                      'rawSms': 'Manual cash transaction',
                      'transactionId': 'MANUAL_${docRef.id}',
                      'categoryId': selCat,
                      'timestamp': FieldValue.serverTimestamp(),
                    };
                    await docRef.set(data);
                    if (type == 'Income') {
                      await _allocateIncome(docRef.id, amt, userId);
                    }
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Transaction added successfully')));
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Failed to add transaction: $e')));
                  }
                },
                child: const Text('Add')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SmartAppBar(
        title: 'Smart Expense Tracker',
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'fetch':
                  _showFetchOptions(context);
                  break;
                case 'add':
                  _addManualTransaction(context);
                  break;
                case 'settings':
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()));
                  break;
                case 'logout':
                  _handleLogout(context);
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'fetch',
                child: Row(
                  children: [
                    Icon(Icons.refresh,
                        color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Text('Fetch SMS'),
                  ],
                ),
              ),
              const PopupMenuItem(
                  value: 'add',
                  child: Row(children: [
                    Icon(Icons.add,
                        color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text('Add Cash')
                  ])),
              const PopupMenuItem(
                  value: 'settings',
                  child: Row(children: [
                    Icon(Icons.settings,
                        color: Colors.grey, size: 20),
                    SizedBox(width: 8),
                    Text('Settings')
                  ])),
              const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout,
                        color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('Logout')
                  ])),
            ],
          )
        ],
      ),
      body: Stack(
          children: _screens
              .asMap()
              .entries
              .map((e) => e.key == _selectedIndex ? e.value : Container())
              .toList()),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: 'Uncategorized'),
          BottomNavigationBarItem(
              icon: Icon(Icons.category), label: 'Categorized'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).colorScheme.surface,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        showUnselectedLabels: true,
      ),
    );
  }
}
