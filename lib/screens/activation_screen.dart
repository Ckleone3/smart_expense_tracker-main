import 'package:flutter/material.dart';

import '../services/license_service.dart';

const String kDeveloperContact = 'info@cksmartsolutions.com';

/// Shown until this device is activated with a valid one-off key.
/// A reshared APK lands here and cannot proceed without a fresh key.
class ActivationScreen extends StatefulWidget {
  /// Called once activation succeeds.
  final VoidCallback onActivated;
  const ActivationScreen({super.key, required this.onActivated});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final LicenseService _license = LicenseService();
  final _keyController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _license.activate(_keyController.text);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case ActivationResult.success:
        widget.onActivated();
        break;
      case ActivationResult.invalidKey:
        setState(() => _error =
            'Invalid activation key. Please check it and try again, or contact the developer.');
        break;
      case ActivationResult.inactive:
        setState(() => _error =
            'This key has been disabled. Contact the developer: $kDeveloperContact');
        break;
      case ActivationResult.usedOnAnotherDevice:
        setState(() => _error =
            'This key is already activated on another phone. Each key works on one device only.\n\nContact the developer for your own key: $kDeveloperContact');
        break;
      case ActivationResult.notSignedIn:
        setState(() => _error = 'Please sign in first, then activate.');
        break;
      case ActivationResult.networkError:
        setState(() => _error =
            'Could not reach the server. Connect to the internet and try again.');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user, size: 72, color: Colors.indigo),
                const SizedBox(height: 16),
                const Text(
                  'Activate your app',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the activation key you received from the developer. '
                  'Each key works on one phone only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _keyController,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _activate(),
                  decoration: const InputDecoration(
                    labelText: 'Activation key',
                    hintText: 'e.g. LEO-7F3A-9K2P',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _activate,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(_busy ? 'Activating…' : 'Activate'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No key? Contact the developer:\n$kDeveloperContact',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
