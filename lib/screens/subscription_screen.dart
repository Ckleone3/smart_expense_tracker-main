import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/subscription_service.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<SubscriptionService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: StreamBuilder<SubscriptionTier>(
        stream: service.tierStream(),
        builder: (context, snapshot) {
          // loading
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // default to free if no data
          final tier = snapshot.data ?? SubscriptionTier.free;
          final isPremium = tier == SubscriptionTier.premium;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // --- Current Plan Card ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Plan: ${isPremium ? "Premium" : "Free"}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isPremium
                            ? 'You have access to all premium features'
                            : 'Upgrade to Premium for more features',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // --- Premium Features Card ---
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Premium Features:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildFeatureItem(context, 'Cloud Storage Sync'),
                      _buildFeatureItem(context, 'Cross-device Access'),
                      _buildFeatureItem(context, 'Secure Data Backup'),
                      _buildFeatureItem(context, 'Advanced Reports'),
                    ],
                  ),
                ),
              ),

              if (!isPremium) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.card_giftcard, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text('Free 7-day trial',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try all Premium features free for 7 days. No payment needed.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _startTrial(context),
                          icon: const Icon(Icons.play_circle_outline),
                          label: const Text('Start free trial'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // extra space so last card can scroll above the button
              const SizedBox(height: 80),
            ],
          );
        },
      ),

      // --- Bottom Action Button ---
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: StreamBuilder<SubscriptionTier>(
          stream: service.tierStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            final isPremium =
                (snapshot.data ?? SubscriptionTier.free) == SubscriptionTier.premium;

            return isPremium
                ? OutlinedButton(
                    onPressed: () => _downgradeToFree(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Downgrade to Free'),
                  )
                : ElevatedButton(
                    onPressed: () => _upgradeToPremium(context),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Upgrade to Premium'),
                  );
          },
        ),
      ),
    );
  }

  Future<void> _startTrial(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('trial_used') ?? false) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Your free trial has already been used.'),
      ));
      return;
    }
    await prefs.setString('trial_start', DateTime.now().toIso8601String());
    await prefs.setBool('trial_used', true);
    messenger.showSnackBar(const SnackBar(
      content: Text('Free trial started — enjoy Premium for 7 days!'),
    ));
  }

  Widget _buildFeatureItem(BuildContext context, String feature) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(Icons.check_circle,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(feature),
        ],
      ),
    );
  }

  Future<void> _upgradeToPremium(BuildContext context) async {
    // Premium is granted only after a verified payment (handled by the backend),
    // never by the app itself — this keeps it from being unlocked for free.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upgrade to Premium'),
        content: const Text(
          'Premium is activated after payment via M-Pesa.\n\n'
          'Mobile payment is coming soon. Once you pay, your account is '
          'upgraded automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _downgradeToFree(BuildContext context) async {
    try {
      await Provider.of<SubscriptionService>(context, listen: false)
          .downgradeToFree();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully downgraded to Free tier')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to downgrade: $e')),
      );
    }
  }
}
