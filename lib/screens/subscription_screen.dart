import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    try {
      await Provider.of<SubscriptionService>(context, listen: false)
          .upgradeToPremium();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Successfully upgraded to Premium!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upgrade: $e')),
      );
    }
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
