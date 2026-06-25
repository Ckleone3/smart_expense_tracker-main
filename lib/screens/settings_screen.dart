import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_expense_tracker/screens/CurrencySettingsScreen.dart';
import 'package:smart_expense_tracker/screens/category_screen.dart';
import 'package:smart_expense_tracker/keyword_settings_screen.dart';
import 'package:smart_expense_tracker/screens/tutorial_screen.dart';
import 'package:smart_expense_tracker/screens/subscription_screen.dart';
import 'package:smart_expense_tracker/screens/ledger_screen.dart';
import 'package:smart_expense_tracker/screens/privacy_policy_screen.dart';

import '../services/storage/storage_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.category),
            title: const Text('Manage Categories'),
            subtitle: const Text('Add or edit categories and subcategories'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoryScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Manage SMS Keywords'),
            subtitle: const Text('Set keywords to fetch transactions'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const KeywordSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Ledger'),
            subtitle: const Text('Auto-tracked payments from SMS, export to CSV'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LedgerScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.monetization_on),
            title: const Text('Manage Currency'),
            subtitle: const Text('Set your preferred currency'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CurrencySettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            subtitle: const Text('How your data and SMS are handled'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('App Tutorial'),
            subtitle: const Text('Learn how to use the app'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TutorialScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.workspace_premium),
            title: const Text('Subscription'),
            subtitle: const Text('Manage your subscription plan'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Active Storage'),
            subtitle: Text(
              context.watch<StorageService>()
                  .currentStorageType
                  .toString()
                  .split('.')
                  .last
                  .toUpperCase(),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          
        ],
      ),
    );
  }
}
