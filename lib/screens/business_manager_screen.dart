import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/business.dart';
import '../services/business_service.dart';
import '../services/sms_service.dart';

/// Manage the businesses/ledgers: each has a name and the keyword(s) that
/// identify its payments in an SMS.
class BusinessManagerScreen extends StatefulWidget {
  const BusinessManagerScreen({super.key});

  @override
  State<BusinessManagerScreen> createState() => _BusinessManagerScreenState();
}

class _BusinessManagerScreenState extends State<BusinessManagerScreen> {
  final BusinessService _service = BusinessService();
  List<Business> _businesses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _service.all();
    if (!mounted) return;
    setState(() {
      _businesses = list;
      _loading = false;
    });
  }

  Future<void> _addOrEdit({Business? existing, String? prefillKeyword}) async {
    final result = await showDialog<Business>(
      context: context,
      builder: (_) => _BusinessDialog(
        service: _service,
        existing: existing,
        prefillKeyword: prefillKeyword,
      ),
    );
    if (result != null) {
      await _service.save(result);
      await _reload();
    }
  }

  Future<void> _delete(Business b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${b.name}"?'),
        content: const Text(
            'Its payments will no longer be tracked. Captured records stay until removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete(b.id);
      await _reload();
    }
  }

  Future<void> _suggest() async {
    final sms = context.read<SmsService>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    await sms.init();
    final suggestions = await _service.suggestKeywords(sms.transactionBox);
    if (!mounted) return;
    Navigator.pop(context); // spinner

    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No payment keywords found in your SMS yet.'),
      ));
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Keywords found in your SMS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Tap one to create a business with it.',
                  style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 8),
            ...suggestions.map((s) => ListTile(
                  leading: const Icon(Icons.tag),
                  title: Text(s.keyword),
                  subtitle: Text(
                      '${s.payments} payment(s) from ${s.payers} payer(s)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addOrEdit(prefillKeyword: s.keyword);
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Businesses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Suggest keywords from SMS',
            onPressed: _suggest,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Add business'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _businesses.isEmpty
              ? _emptyState()
              : ListView.separated(
                  itemCount: _businesses.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final b = _businesses[i];
                    return ListTile(
                      leading: const Icon(Icons.store),
                      title: Text(b.name.isEmpty ? '(unnamed)' : b.name),
                      subtitle: Text(b.keywords.isEmpty
                          ? 'No keywords yet'
                          : 'Keywords: ${b.keywords.join(', ')}'),
                      onTap: () => _addOrEdit(existing: b),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _delete(b),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No businesses yet.\nAdd one with the keyword(s) that appear in its '
              'payment SMS (e.g. your paybill account).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _suggest,
              icon: const Icon(Icons.search),
              label: const Text('Suggest from my SMS'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessDialog extends StatefulWidget {
  final BusinessService service;
  final Business? existing;
  final String? prefillKeyword;

  const _BusinessDialog({required this.service, this.existing, this.prefillKeyword});

  @override
  State<_BusinessDialog> createState() => _BusinessDialogState();
}

class _BusinessDialogState extends State<_BusinessDialog> {
  late final TextEditingController _name;
  late final TextEditingController _keywords;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _keywords = TextEditingController(
      text: widget.existing != null
          ? widget.existing!.keywords.join('\n')
          : (widget.prefillKeyword ?? ''),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add business' : 'Edit business'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Business name',
                hintText: 'e.g. Cheruiyot Rentals',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keywords,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Keywords (one per line)',
                hintText: 'e.g. ANNE-577715',
                helperText: 'Words/accounts that appear in this business’s SMS',
              ),
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
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final name = _name.text.trim();
    final keywords = _keywords.text
        .split(RegExp(r'[\n,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a business name.')),
      );
      return;
    }
    if (keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one keyword to match payments.')),
      );
      return;
    }
    final b = (widget.existing ??
            Business(id: widget.service.newId(), name: '', keywords: const []))
        .copyWith(name: name, keywords: keywords);
    Navigator.pop(context, b);
  }
}
