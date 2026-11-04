import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/business_undo.dart';
import '../services/google_sheets_service.dart';
import '../services/sms_service.dart' as sms;

/// Transactions recorded to business sheets from this phone, newest first,
/// each with an Undo.
class BusinessRecordsScreen extends StatefulWidget {
  const BusinessRecordsScreen({super.key});

  @override
  State<BusinessRecordsScreen> createState() => _BusinessRecordsScreenState();
}

class _BusinessRecordsScreenState extends State<BusinessRecordsScreen> {
  final _svc = GoogleSheetsService.instance;
  List<BusinessRecord> _items = [];
  bool _loading = true;
  final Set<String> _busy = {};

  /// True once anything was undone, so the caller can refresh its list.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _svc.records();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _undo(BusinessRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo this record?'),
        content: Text(
            'The row for "${r.description}" will be deleted from ${r.workbookName} › ${r.sheet}, and the transaction will go back to To Sort.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Undo')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(r);
  }

  Future<void> _run(BusinessRecord r, {bool sheetAlreadyHandled = false}) async {
    final smsService = context.read<sms.SmsService>();
    setState(() => _busy.add(r.itemId));
    try {
      final msg = await undoBusinessRecord(r, smsService,
          sheetAlreadyHandled: sheetAlreadyHandled);
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), behavior: SnackBarBehavior.floating));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      final force = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Couldn't remove the row"),
          content: Text(
              '$e\n\nYou can still move the transaction back to To Sort and delete the row in Google Sheets yourself.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Move back anyway')),
          ],
        ),
      );
      if (force == true && mounted) {
        setState(() => _busy.remove(r.itemId));
        return _run(r, sheetAlreadyHandled: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(r.itemId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'Ksh ');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Recorded to business')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Nothing recorded yet.\n\nTransactions you record to a business sheet appear here, so you can undo them.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _items[i];
                      final busy = _busy.contains(r.itemId);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: r.isIncoming
                              ? Colors.green[100]
                              : Colors.red[100],
                          child: Text(r.isIncoming ? 'IN' : 'OUT',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: r.isIncoming
                                      ? Colors.green[800]
                                      : Colors.red[800])),
                        ),
                        title: Text(r.description,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${money.format(r.amount)} · ${DateFormat('dd/MM/yyyy HH:mm').format(r.date)}\n'
                          '${r.workbookName} › ${r.sheet}',
                        ),
                        isThreeLine: true,
                        trailing: busy
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : TextButton.icon(
                                onPressed: () => _undo(r),
                                icon: const Icon(Icons.undo),
                                label: const Text('Undo'),
                              ),
                      );
                    },
                  ),
      ),
    );
  }
}
