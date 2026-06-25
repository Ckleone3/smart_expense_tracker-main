import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/business.dart';
import '../models/rent_payment.dart';
import '../services/ledger_service.dart';
import '../services/sms_service.dart';
import 'business_manager_screen.dart';

/// Universal ledger: pick a business, see its payments (matched from SMS by its
/// keywords), and export that business's CSV.
class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final LedgerService _service = LedgerService();
  final _currency = NumberFormat.currency(symbol: 'KES ', decimalDigits: 2);

  List<Business> _businesses = [];
  Business? _selected;
  List<RentPayment> _rows = [];
  String _filter = 'All'; // 'All' | 'In' | 'Out'
  late DateTimeRange _range;
  bool _loading = true;
  String? _error;

  /// Rows after applying the In/Out/All filter.
  List<RentPayment> get _visibleRows =>
      _filter == 'All' ? _rows : _rows.where((p) => p.bank == _filter).toList();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    final sms = context.read<SmsService>();
    try {
      await _service.ensureNotificationPermission();
      await _service.businesses.pushKeywordsToNative();
      await sms.init();
      try {
        await sms.initializeSmsStore();
      } catch (_) {/* non-fatal */}
      await _service.backfillFromTransactions(sms.transactionBox);
      await _service.syncFromNative();
      await _loadBusinessesAndQuery();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadBusinessesAndQuery() async {
    setState(() => _loading = true);
    final list = await _service.businesses.all();
    Business? selected = _selected;
    if (selected == null || !list.any((b) => b.id == selected!.id)) {
      selected = list.isNotEmpty ? list.first : null;
    }
    final rows = selected == null
        ? <RentPayment>[]
        : await _service.query(selected, start: _range.start, end: _range.end);
    if (!mounted) return;
    setState(() {
      _businesses = list;
      _selected = selected;
      _rows = rows;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _refresh() async {
    final sms = context.read<SmsService>();
    try {
      await sms.initializeSmsStore();
    } catch (_) {/* non-fatal */}
    await _service.syncFromNative();
    await _service.backfillFromTransactions(sms.transactionBox);
    await _loadBusinessesAndQuery();
  }

  Future<void> _openBusinesses() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BusinessManagerScreen()),
    );
    await _refresh(); // keywords may have changed -> re-capture history
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) {
      _range = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
      );
      await _loadBusinessesAndQuery();
    }
  }

  Future<void> _export() async {
    final rows = _visibleRows;
    if (_selected == null || rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export for this period.')),
      );
      return;
    }
    final scope = _filter == 'All'
        ? ''
        : _filter == 'In'
            ? ' (Money In)'
            : ' (Money Out)';
    final rangeLabel =
        '${DateFormat('dd MMM').format(_range.start)} - ${DateFormat('dd MMM yyyy').format(_range.end)}$scope';
    try {
      await _service.exportCsv(_selected!, rows, rangeLabel: rangeLabel);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _deleteRow(RentPayment p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this payment?'),
        content: Text(
            'Removes ${p.tenantName} (${_currency.format(p.amount)}) and won\'t capture it again.'),
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
      await _service.delete(p);
      setState(() => _rows.remove(p));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.store),
            tooltip: 'My businesses',
            onPressed: _openBusinesses,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Check for new payments',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      floatingActionButton: (_selected != null && _visibleRows.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _export,
              icon: const Icon(Icons.download),
              label: const Text('Export CSV'),
            )
          : null,
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load the ledger.\n\n$_error',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_businesses.isEmpty) return _setupState();

    return Column(
      children: [
        _selector(),
        _filterControl(),
        _summaryCard(),
        const Divider(height: 1),
        Expanded(
          child: _visibleRows.isEmpty ? _noPaymentsState() : _tableView(),
        ),
      ],
    );
  }

  Widget _filterControl() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'All', label: Text('All')),
          ButtonSegment(
              value: 'In', label: Text('In'), icon: Icon(Icons.south_west)),
          ButtonSegment(
              value: 'Out', label: Text('Out'), icon: Icon(Icons.north_east)),
        ],
        selected: {_filter},
        onSelectionChanged: (s) => setState(() => _filter = s.first),
      ),
    );
  }

  Widget _selector() {
    if (_businesses.length == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(_selected?.name ?? '',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: DropdownButtonFormField<String>(
        initialValue: _selected?.id,
        decoration: const InputDecoration(
          labelText: 'Business',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: _businesses
            .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
            .toList(),
        onChanged: (id) async {
          final b = _businesses.firstWhere((e) => e.id == id);
          setState(() => _selected = b);
          await _loadBusinessesAndQuery();
        },
      ),
    );
  }

  Widget _summaryCard() {
    final rangeText =
        '${DateFormat('dd MMM yyyy').format(_range.start)}  —  ${DateFormat('dd MMM yyyy').format(_range.end)}';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: ListTile(
          onTap: _pickRange,
          leading: const Icon(Icons.date_range),
          title: Text(rangeText),
          subtitle: Text(
            '${_visibleRows.length} payment(s)  •  ${_currency.format(_service.total(_visibleRows))}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          trailing: const Icon(Icons.edit_calendar),
        ),
      ),
    );
  }

  Widget _tableView() {
    const headers = LedgerService.csvHeaders;
    List<DataCell> dataCells(List<String> v, {bool bold = false}) => [
          for (var i = 0; i < headers.length; i++)
            DataCell(Text(i < v.length ? v[i] : '',
                style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null)),
        ];
    final table = DataTable(
      headingRowColor: WidgetStateProperty.all(
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)),
      columns: [
        for (final h in headers)
          DataColumn(
              label: Text(h, style: const TextStyle(fontWeight: FontWeight.bold))),
        const DataColumn(label: Text('')),
      ],
      rows: [
        for (final p in _visibleRows)
          DataRow(cells: [
            ...dataCells(_service.csvRowFor(p)),
            DataCell(IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              tooltip: 'Remove (wrong match)',
              onPressed: () => _deleteRow(p),
            )),
          ]),
        DataRow(cells: [
          ...dataCells(_service.totalRow(_visibleRows), bold: true),
          const DataCell(Text('')),
        ]),
      ],
    );

    // InteractiveViewer gives pinch-to-zoom + pan (drag) around the table.
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.pinch, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              const Text('Pinch to zoom • drag to pan',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const Spacer(),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            panEnabled: true,
            scaleEnabled: true,
            minScale: 0.5,
            maxScale: 5.0,
            boundaryMargin: const EdgeInsets.all(120),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: table,
            ),
          ),
        ),
      ],
    );
  }

  Widget _setupState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 64, color: Colors.indigo),
            const SizedBox(height: 16),
            const Text(
              'Track any business from SMS',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add a business with the keyword(s) that appear in its payment SMS '
              '(e.g. your paybill account). Every payment is captured into its '
              'ledger and exportable as CSV.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _openBusinesses,
              icon: const Icon(Icons.add_business),
              label: const Text('Add your first business'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noPaymentsState() {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.inbox, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No payments for this business in this period.\n'
                'New ones will appear automatically.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
