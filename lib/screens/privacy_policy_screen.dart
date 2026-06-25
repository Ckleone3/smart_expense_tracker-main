import 'package:flutter/material.dart';

/// In-app privacy policy. NOTE: this is a starting draft — have it reviewed and
/// also host the same text at a public URL (required by app stores and useful
/// for trust). Replace the bracketed placeholders before publishing.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String policyText = '''
PRIVACY POLICY

Last updated: 23 June 2026
App: Smart Expense Tracker  •  Provider: CKSmartsolutions  •  Contact: info@cksmartsolutions.com

This app helps you track money automatically by reading transaction SMS on your
phone. Your privacy matters. This policy explains what we access, why, and your
choices.

1. WHAT WE ACCESS
• SMS messages: We read SMS to detect financial transactions (e.g. M-Pesa and
  bank payment alerts). We look for amounts, sender/payer names, dates and
  references. We do NOT read or use one-time passwords (OTP), personal chats are
  ignored, and non-financial messages are not stored beyond detection.
• Account info: Your email/name from Google Sign-In, used to identify your
  account.
• Notifications: To alert you when a tracked payment (e.g. rent) is received.

2. HOW WE USE IT
• To automatically record your income/expenses and (for landlords) rent
  payments, categorise them, and produce reports/CSV exports.
• To show alerts for new tracked payments.

3. WHERE YOUR DATA IS STORED
• On your device: transaction and rent data are stored locally on your phone.
• In the cloud (Premium only): if you subscribe to Premium, your data is backed
  up and synced via Google Firebase (Firestore) so you can access it across
  devices. Free users' data stays on the device.

4. SHARING
• We do NOT sell your data. We do NOT share it with advertisers.
• We use Google Firebase (authentication, database, crash reporting) as our
  service provider. Your data is subject to Google's security.

5. YOUR CHOICES & CONTROL
• The app only reads SMS after you grant SMS permission, which you can revoke any
  time in your phone Settings (some features will stop working).
• You can delete entries in the app, sign out, or request full account/data
  deletion by contacting info@cksmartsolutions.com.

6. DATA RETENTION
• Local data remains until you delete it or uninstall the app.
• Cloud data (Premium) remains until you delete it or request deletion.

7. CHILDREN
• This app is not intended for children under 18.

8. CHANGES
• We may update this policy; changes appear here with a new "Last updated" date.

9. CONTACT
• Questions or data-deletion requests: info@cksmartsolutions.com
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(policyText),
      ),
    );
  }
}
