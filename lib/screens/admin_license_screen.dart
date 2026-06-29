import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/license_service.dart';

/// Developer-only panel to generate and manage activation keys.
/// Reachable from Settings only when signed in as an admin email.
class AdminLicenseScreen extends StatelessWidget {
  AdminLicenseScreen({super.key});

  final LicenseService _license = LicenseService();

  Future<void> _generate(BuildContext context) async {
    final noteController = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New activation key'),
        content: TextField(
          controller: noteController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Client name / note (optional)',
            hintText: 'e.g. Anne — paid 4 Jul',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, noteController.text),
              child: const Text('Generate')),
        ],
      ),
    );
    if (note == null) return; // cancelled
    final key = await _license.createLicense(note: note.trim());
    if (context.mounted) _showKey(context, key);
  }

  void _showKey(BuildContext context, String key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Key created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(key,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Give this to the client. It works on one phone only.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Key copied')),
              );
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Activation Keys')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _generate(context),
        icon: const Icon(Icons.add),
        label: const Text('New key'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _license.licensesStream(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load keys.\n${snap.error}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No keys yet. Tap "New key" to create one for a client.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();
              final active = data['active'] == true;
              final deviceId = (data['deviceId'] as String?) ?? '';
              final note = (data['note'] as String?) ?? '';
              final bound = deviceId.isNotEmpty;
              final created = (data['createdAt'] as Timestamp?)?.toDate();

              final status = !active
                  ? 'Disabled'
                  : bound
                      ? 'Activated'
                      : 'Unused';
              final statusColor = !active
                  ? Colors.grey
                  : bound
                      ? Colors.green
                      : Colors.orange;

              return ListTile(
                leading: Icon(Icons.vpn_key, color: statusColor),
                title: SelectableText(d.id,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text([
                  status,
                  if (note.isNotEmpty) note,
                  if (created != null) dateFmt.format(created),
                ].join('  •  ')),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'copy':
                        Clipboard.setData(ClipboardData(text: d.id));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Key copied')));
                        break;
                      case 'toggle':
                        await _license.setActive(d.id, !active);
                        break;
                      case 'reset':
                        await _license.resetDevice(d.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Key freed — client can activate on a new phone')));
                        }
                        break;
                      case 'delete':
                        await _license.deleteLicense(d.id);
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'copy', child: Text('Copy key')),
                    PopupMenuItem(
                        value: 'toggle',
                        child: Text(active ? 'Disable' : 'Enable')),
                    if (bound)
                      const PopupMenuItem(
                          value: 'reset', child: Text('Reset device')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
