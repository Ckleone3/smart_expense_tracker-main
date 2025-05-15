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

import 'firebase_options.dart';

// <-- Import your centralized theme
import 'services/storage/storage_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Send uncaught Flutter errors to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Capture errors outside the Flutter framework
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
      Provider<SmsService>(create: (_) => SmsService()),
      ChangeNotifierProvider<SubscriptionService>(
        create: (_) => SubscriptionService(),
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
  bool _isFetching = false;
  late SmsService _smsService;

  static final List<Widget> _screens = [
    const UncategorizedScreen(),
    const CategorizedScreen(),
    const ReportsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _smsService = Provider.of<SmsService>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // First-launch check
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
      if (!hasSeenOnboarding) {
        await prefs.setBool('hasSeenOnboarding', true);
        // show tutorial screen on first launch
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TutorialScreen()),
        );
      }

      // then do your normal SMS sync
      _initializeServiceAndSync();
    });
  }

  @override
  void dispose() {
    _smsService.dispose();
    super.dispose();
  }

  Future<void> _initializeServiceAndSync() async {
    setState(() {
      _isFetching = true;
    });
    try {
      await _smsService.init();
      final newMessages = await _smsService.initializeSmsStore();
      if (newMessages > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Stored $newMessages new SMS messages'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during initial SMS sync: $e'),
        ),
      );
    } finally {
      setState(() {
        _isFetching = false;
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Fetch SMS Transactions'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                // Select Day
                DialogButton(
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

                // Select Date Range
                DialogButton(
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

                // Select Month
                DialogButton(
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
        );
      },
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
    final years =
        List.generate(currentYear - 2019, (index) => currentYear - index);
    final months = [
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
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<int>(
                  value: selectedYear,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: years
                      .map((year) => DropdownMenuItem<int>(
                            value: year,
                            child: Text(year.toString()),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedYear = value;
                    });
                  },
                  hint: const Text('Select Year'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Month',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<int>(
                  value: selectedMonth,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: months
                      .asMap()
                      .entries
                      .map((entry) => DropdownMenuItem<int>(
                            value: entry.key + 1,
                            child: Text(entry.value),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedMonth = value;
                    });
                  },
                  hint: const Text('Select Month'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              onPressed: () {
                if (selectedYear != null && selectedMonth != null) {
                  final selectedDate =
                      DateTime(selectedYear!, selectedMonth!, 1);
                  Navigator.pop(context);
                  _fetchSms('month', selectedDate);
                }
              },
              label: const Text('Fetch'),
            ),
          ],
        ),
      ),
    );
  }

  void _fetchSms(String fetchType, DateTime referenceDate,
      {DateTime? rangeEnd}) async {
    Navigator.pop(context);
    setState(() {
      _isFetching = true;
    });
    try {
      final result = await _smsService.fetchTransactions(
        fetchType,
        referenceDate,
        rangeEnd: rangeEnd,
      );
      final parsedCount = result['parsed']!;
      if (parsedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Retrieved $parsedCount SMS transactions from store'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching SMS transactions found for this date'),
          ),
        );
      }
    } catch (e) {
      if (e.toString().contains('NO_KEYWORDS_AVAILABLE')) {
        _showNoKeywordsDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching transactions: $e'),
          ),
        );
      }
    } finally {
      setState(() {
        _isFetching = false;
      });
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
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            label: const Text('Go to Settings'),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _fetchCategories(String type) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return [];
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: type)
        .get();
    return snapshot.docs.map((doc) => doc['name'] as String).toList();
  }

  Future<void> _allocateIncome(
      String transactionId, double amount, String userId) async {
    final expenseCategories = await FirebaseFirestore.instance
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

      await FirebaseFirestore.instance
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

  Future<double> _calculateExpensePercentageTotal() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return 0;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('categories')
        .where('type', isEqualTo: 'Expense')
        .get();
    double total = 0;
    for (var doc in snapshot.docs) {
      total += (doc['percentage'] as num?)?.toDouble() ?? 0;
    }
    return total;
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
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedCategory;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  value: type,
                  items: ['Income', 'Expense']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      type = value;
                      selectedCategory = null;
                    });
                  },
                  validator: (value) =>
                      value == null ? 'Please select a type' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter an amount';
                    }
                    if (double.tryParse(value) == null ||
                        double.parse(value) <= 0) {
                      return 'Please enter a valid positive amount';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter a description'
                      : null,
                ),
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
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                      child: const Text('Pick Date'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (type != null)
                  FutureBuilder<List<String>>(
                    future: _fetchCategories(type!),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircularProgressIndicator();
                      }
                      final categories = snapshot.data!;
                      return DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Category (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        value: selectedCategory,
                        items: categories
                            .map((cat) =>
                                DropdownMenuItem(value: cat, child: Text(cat)))
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedCategory = value;
                          });
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (type == null ||
                    amountController.text.isEmpty ||
                    descriptionController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please fill all required fields')),
                  );
                  return;
                }
                final amount = double.tryParse(amountController.text);
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please enter a valid amount')),
                  );
                  return;
                }

                if (type == 'Income') {
                  final expenseTotal = await _calculateExpensePercentageTotal();
                  if (expenseTotal != 100) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Expense categories must total 100% to allocate income.'),
                      ),
                    );
                    return;
                  }
                }

                try {
                  final docRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('transactions')
                      .doc();
                  final transactionData = {
                    'type': type,
                    'amount': amount,
                    'description': descriptionController.text,
                    'date': selectedDate.toIso8601String(),
                    'rawSms': 'Manual cash transaction',
                    'transactionId': 'MANUAL_${docRef.id}',
                    'categoryId': selectedCategory,
                    'timestamp': FieldValue.serverTimestamp(),
                  };

                  await docRef.set(transactionData);

                  if (type == 'Income') {
                    await _allocateIncome(docRef.id, amount, userId);
                  }

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Transaction added successfully')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add transaction: $e')),
                  );
                }
              },
              child: const Text('Add'),
            ),
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
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  break;
                case 'logout':
                  _handleLogout(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'fetch',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Fetch SMS'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.add, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Add Cash'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Settings'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.black54),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          _screens[_selectedIndex],
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Uncategorized',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.category),
            label: 'Categorized',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
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
