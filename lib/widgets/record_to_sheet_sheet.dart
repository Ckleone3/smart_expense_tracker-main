import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/business_workbooks_screen.dart';
import '../services/google_sheets_service.dart';

class RecordToSheetResult {
  final BusinessWorkbook workbook;
  final String sheet;
  final AppendResult result;
  RecordToSheetResult(this.workbook, this.sheet, this.result);

  /// Value stored as the transaction's categoryId once recorded.
  String get categoryLabel => '$kBusinessCategoryPrefix ${workbook.name} › $sheet';
}

/// Bottom sheet that lets the user pick a workbook and a worksheet, then
/// appends [entries] to it. Returns null if dismissed without recording.
Future<RecordToSheetResult?> showRecordToSheet(
    BuildContext context, List<SheetEntry> entries) {
  return showModalBottomSheet<RecordToSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _RecordToSheet(entries: entries),
  );
}

class _RecordToSheet extends StatefulWidget {
  final List<SheetEntry> entries;
  const _RecordToSheet({required this.entries});

  @override
  State<_RecordToSheet> createState() => _RecordToSheetState();
}

class _RecordToSheetState extends State<_RecordToSheet> {
  final _svc = GoogleSheetsService.instance;
  final _filter = TextEditingController();

  List<BusinessWorkbook> _workbooks = [];
  BusinessWorkbook? _workbook;
  List<String> _sheets = [];
  String? _sheet;
  String? _lastSheet;

  bool _loadingWorkbooks = true;
  bool _loadingSheets = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    List<BusinessWorkbook> list = [];
    String? lastWorkbookId;
    try {
      list = await _svc.workbooks();
      final last = await _svc.last();
      lastWorkbookId = last.workbookId;
      _lastSheet = last.sheet;
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load workbooks: $e');
    }
    if (!mounted) return;
    setState(() {
      _workbooks = list;
      _loadingWorkbooks = false;
    });
    if (list.isNotEmpty) {
      final pick = list.firstWhere((w) => w.id == lastWorkbookId,
          orElse: () => list.first);
      _selectWorkbook(pick);
    }
  }

  Future<void> _selectWorkbook(BusinessWorkbook w) async {
    setState(() {
      _workbook = w;
      _sheets = [];
      _sheet = null;
      _error = null;
      _loadingSheets = true;
      _filter.clear();
    });
    try {
      final info = await _svc.describe(w.spreadsheetId);
      if (!mounted || _workbook?.id != w.id) return;
      setState(() {
        _sheets = info.sheets;
        if (_lastSheet != null && info.sheets.contains(_lastSheet)) {
          _sheet = _lastSheet;
        } else if (info.sheets.length == 1) {
          _sheet = info.sheets.first;
        }
      });
    } catch (e) {
      if (mounted && _workbook?.id == w.id) setState(() => _error = '$e');
    } finally {
      if (mounted && _workbook?.id == w.id) {
        setState(() => _loadingSheets = false);
      }
    }
  }

  Future<void> _addWorkbook() async {
    final wb = await showAddWorkbookDialog(context);
    if (wb == null) return;
    final list = await _svc.workbooks();
    if (!mounted) return;
    setState(() => _workbooks = list);
    _selectWorkbook(wb);
  }

  Future<void> _newSheet() async {
    final wb = _workbook;
    if (wb == null) return;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New sheet'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
              labelText: 'Sheet name', hintText: 'e.g. Constructions'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    if (_sheets.any((s) => s.toLowerCase() == name.toLowerCase())) {
      setState(() => _sheet = _sheets
          .firstWhere((s) => s.toLowerCase() == name.toLowerCase()));
      return;
    }
    setState(() {
      _loadingSheets = true;
      _error = null;
    });
    try {
      await _svc.createSheet(wb.spreadsheetId, name);
      if (!mounted) return;
      setState(() {
        _sheets = [..._sheets, name];
        _sheet = name;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingSheets = false);
    }
  }

  Future<void> _record() async {
    final wb = _workbook, sheet = _sheet;
    if (wb == null || sheet == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await _svc.append(
        wb.spreadsheetId,
        sheet,
        widget.entries,
        recordedBy: FirebaseAuth.instance.currentUser?.email ??
            _svc.signedInEmail ??
            '',
      );
      await _svc.rememberLast(wb.id, sheet);
      if (mounted) {
        Navigator.pop(context, RecordToSheetResult(wb, sheet, result));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _switchAccount() async {
    try {
      await _svc.switchAccount();
      if (mounted) setState(() {});
      if (_workbook != null) _selectWorkbook(_workbook!);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.entries.fold<double>(0, (s, e) => s + e.amount);
    final n = widget.entries.length;
    final query = _filter.text.trim().toLowerCase();
    final visibleSheets = query.isEmpty
        ? _sheets
        : _sheets.where((s) => s.toLowerCase().contains(query)).toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Record to business sheet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              n == 1
                  ? '${widget.entries.first.description} · ${NumberFormat.currency(symbol: 'Ksh ').format(total)}'
                  : '$n transactions · ${NumberFormat.currency(symbol: 'Ksh ').format(total)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),

            // ── Workbook ─────────────────────────────────────────
            Text('Workbook', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (_loadingWorkbooks)
              const LinearProgressIndicator()
            else if (_workbooks.isEmpty)
              OutlinedButton.icon(
                onPressed: _addWorkbook,
                icon: const Icon(Icons.add_link),
                label: const Text('Link a Google Sheets workbook'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final w in _workbooks)
                    ChoiceChip(
                      avatar: const Icon(Icons.table_chart, size: 18),
                      label: Text(w.name),
                      selected: _workbook?.id == w.id,
                      onSelected: _saving ? null : (_) => _selectWorkbook(w),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Link'),
                    onPressed: _saving ? null : _addWorkbook,
                  ),
                ],
              ),

            // ── Sheet ────────────────────────────────────────────
            if (_workbook != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                      child: Text('Sheet', style: theme.textTheme.titleSmall)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reload sheets',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadingSheets || _saving
                        ? null
                        : () => _selectWorkbook(_workbook!),
                  ),
                ],
              ),
              if (_sheets.length > 8) ...[
                TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a sheet',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_loadingSheets)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in visibleSheets)
                      ChoiceChip(
                        label: Text(s),
                        selected: _sheet == s,
                        onSelected:
                            _saving ? null : (_) => setState(() => _sheet = s),
                      ),
                    if (_error == null)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('New sheet'),
                        onPressed: _saving ? null : _newSheet,
                      ),
                  ],
                ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style:
                        TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _sheet == null || _saving || _loadingSheets
                    ? null
                    : _record,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload),
                label: Text(_sheet == null
                    ? 'Choose a sheet'
                    : 'Record to "$_sheet"'),
              ),
            ),
            if (_svc.signedInEmail != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text('Google account: ${_svc.signedInEmail}',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _switchAccount,
                      child: const Text('Switch'),
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
