import 'package:flutter/material.dart';
import 'package:smart_expense_tracker/screens/category_screen.dart';
import 'package:smart_expense_tracker/screens/reports_screen.dart';
import 'package:smart_expense_tracker/screens/sms_filter_screen.dart';
import 'package:smart_expense_tracker/screens/expense_list_screen.dart';
import 'package:smart_expense_tracker/screens/settings_screen.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('App Tutorial'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome to Smart Expense Tracker!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text(
              'Here is how you can use the app:',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: Icon(Icons.dashboard),
                    title: Text('Dashboard'),
                    subtitle: Text('View your overall expenses and insights.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.category),
                    title: Text('Categories'),
                    subtitle: Text(
                        'Organize your expenses into categories. Navigate to the Category Screen to add or edit categories.'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CategoryScreen())),
                  ),
                  ListTile(
                    leading: Icon(Icons.report),
                    title: Text('Reports'),
                    subtitle: Text(
                        'Generate detailed reports of your expenses. Access the Reports Screen for insights.'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReportsScreen())),
                  ),
                  ListTile(
                    leading: Icon(Icons.sms),
                    title: Text('SMS Filter'),
                    subtitle: Text(
                        'Fetch and filter SMS transactions. Use the SMS Filter Screen to manage SMS data.'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SmsFilterScreen())),
                  ),
                  ListTile(
                    leading: Icon(Icons.list),
                    title: Text('Expense List'),
                    subtitle: Text(
                        'View and manage your expenses. Go to the Expense List Screen for detailed expense tracking.'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ExpenseListScreen())),
                  ),
                  ListTile(
                    leading: Icon(Icons.settings),
                    title: Text('Settings'),
                    subtitle: Text(
                        'Customize the app to suit your needs. Access the Settings Screen for app configurations.'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen())),
                  ),
                  ListTile(
                    leading: Icon(Icons.category),
                    title: Text('Category Screen'),
                    subtitle: Text(
                        'Manage categories for income and expenses. Add, edit, or delete categories and ensure expense percentages do not exceed 100%.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.report),
                    title: Text('Reports Screen'),
                    subtitle: Text(
                        'Generate and view reports for financial insights. Analyze income and expenses using charts.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.sms),
                    title: Text('SMS Filter Screen'),
                    subtitle: Text(
                        'Fetch and filter SMS transactions. Select a date range and view parsed transactions.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.list),
                    title: Text('Expense List Screen'),
                    subtitle: Text(
                        'View and manage a list of expenses. Edit or delete expenses as needed.'),
                  ),
                  ListTile(
                    leading: Icon(Icons.settings),
                    title: Text('Settings Screen'),
                    subtitle: Text(
                        'Customize app settings. Manage categories, SMS keywords, currency, and access the tutorial.'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
