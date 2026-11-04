import 'package:flutter/material.dart';

import '../services/google_sheets_service.dart';
import 'business_records_screen.dart';

/// Asks for a Google Sheets link, verifies access and saves it as a linked
/// workbook. Returns the saved workbook, or null if cancelled.
Future<BusinessWorkbook?> showAddWorkbookDialog(BuildContext context) {
  return showDialog<BusinessWorkbook>(
    context: context,
    builder: (_) => const _AddWorkbookDialog(),
  );
}

class _AddWorkbookDialog extends StatefulWidget {
  const _AddWorkbookDialog();

  @override
  State<_AddWorkbookDialog> createState() => _AddWorkbookDialogState();
}

class _AddWorkbookDialogState extends State<_AddWorkbookDialog> {
  final _link = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = GoogleSheetsService.parseSpreadsheetId(_link.text);
    if (id == null) {
      setState(() => _error = 'Paste the workbook link from Google Sheets.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = GoogleSheetsService.instance;
      final info = await svc.describe(id); // verifies access
      final name = _name.text.trim().isEmpty ? info.title : _name.text.trim();
      final wb = BusinessWorkbook(
        id: 'wb_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        spreadsheetId: id,
      );
      await svc.saveWorkbook(wb);
      if (mounted) Navigator.pop(context, wb);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Link a workbook'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Open the workbook in Google Sheets, tap Share › Copy link, and paste it here.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Workbook link',
                hintText: 'https://docs.google.com/spreadsheets/d/…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
                helperText: 'Defaults to the workbook title',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Link'),
        ),
      ],
    );
  }
}

/// Lists linked business workbooks; add or unlink them.
class BusinessWorkbooksScreen extends StatefulWidget {
  const BusinessWorkbooksScreen({super.key});

  @override
  State<BusinessWorkbooksScreen> createState() =>
      _BusinessWorkbooksScreenState();
}

class _BusinessWorkbooksScreenState extends State<BusinessWorkbooksScreen> {
  final _svc = GoogleSheetsService.instance;
  List<BusinessWorkbook> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _svc.workbooks();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    if (await showAddWorkbookDialog(context) != null) _reload();
  }

  Future<void> _remove(BusinessWorkbook w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink workbook?'),
        content: Text(
            '"${w.name}" will be removed from the app. The Google Sheet itself is not changed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unlink', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await _svc.deleteWorkbook(w.id);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Workbooks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Recorded to business (undo)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BusinessRecordsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_link),
        label: const Text('Link workbook'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No workbooks linked yet.\n\nLink a Google Sheets workbook to record business transactions from the To Sort screen. Each sheet (tab) in the workbook is a payable.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (final w in _items)
                      ListTile(
                        leading: const Icon(Icons.table_chart,
                            color: Color(0xFF188038)),
                        title: Text(w.name),
                        subtitle: Text(w.spreadsheetId,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.link_off),
                          tooltip: 'Unlink',
                          onPressed: () => _remove(w),
                        ),
                      ),
                  ],
                ),
    );
  }
}
