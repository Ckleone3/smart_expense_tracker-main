import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/business_workbooks_screen.dart';
import '../services/google_sheets_service.dart';
import '../services/personal_category.dart';

class RecordToSheetResult {
  final BusinessWorkbook workbook;
  final String sheet;
  final AppendResult result;

  /// Personal category to also put the transactions in, if chosen.
  final String? personalCategory;

  /// True if the transactions are income (decides how [personalCategory]
  /// is applied).
  final bool income;

  RecordToSheetResult(this.workbook, this.sheet, this.result,
      {this.personalCategory, this.income = false});

  /// Business label used when the transaction is only recorded to the sheet.
  String get businessLabel => '$kBusinessCategoryPrefix ${workbook.name} › $sheet';

  /// Value stored as the transaction's categoryId once recorded.
  String get categoryLabel => personalCategory ?? businessLabel;
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

  // Also record into a personal (Firestore) category.
  bool _alsoPersonal = false;
  bool _loadingCats = false;
  List<String> _cats = [];
  String? _cat;

  /// True if all entries are income, false if all are expenses, null if mixed.
  late final bool? _allIncome = () {
    final kinds = widget.entries.map((e) => e.isIncoming).toSet();
    return kinds.length == 1 ? kinds.first : null;
  }();

  String get _catType => _allIncome == true ? 'Income' : 'Expense';

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

  Future<void> _togglePersonal(bool on) async {
    setState(() {
      _alsoPersonal = on;
      _error = null;
    });
    if (!on || _cats.isNotEmpty) return;
    setState(() => _loadingCats = true);
    try {
      final list = await PersonalCategories.names(_catType);
      if (!mounted) return;
      setState(() {
        _cats = list;
        if (list.length == 1) _cat = list.first;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load your categories: $e');
    } finally {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  Future<void> _record() async {
    final wb = _workbook, sheet = _sheet;
    if (wb == null || sheet == null) return;
    final personal = _alsoPersonal ? _cat : null;
    if (_alsoPersonal && personal == null) {
      setState(() => _error = 'Pick one of your categories, or turn off '
          '"Also save to my categories".');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Check the personal category first so nothing is written if it fails.
      if (personal != null) {
        final total = widget.entries.fold<double>(0, (s, e) => s + e.amount);
        final problem = await PersonalCategories.check(
            income: _allIncome == true, category: personal, total: total);
        if (problem != null) {
          if (mounted) setState(() => _error = problem);
          return;
        }
      }
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
        Navigator.pop(
            context,
            RecordToSheetResult(wb, sheet, result,
                personalCategory: personal, income: _allIncome == true));
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

  static const _sheetGreen = Color(0xFF188038);

  Widget _buildSheetList(ThemeData theme, List<String> sheets) {
    final scheme = theme.colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.38;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: sheets.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('No sheets match "${_filter.text.trim()}"',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: sheets.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (_, i) {
                final name = sheets[i];
                final selected = name == _sheet;
                final lastUsed = name == _lastSheet;
                return Material(
                  color: selected
                      ? scheme.primaryContainer.withValues(alpha: 0.6)
                      : Colors.transparent,
                  child: ListTile(
                    dense: true,
                    enabled: !_saving,
                    leading: Icon(Icons.grid_on,
                        color: selected ? scheme.primary : _sheetGreen),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: lastUsed ? const Text('Last used') : null,
                    trailing: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                    onTap: () => setState(() => _sheet = name),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPersonalSection(ThemeData theme) {
    final scheme = theme.colorScheme;
    final mixed = _allIncome == null;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: _alsoPersonal ? scheme.primary : scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            secondary: Icon(Icons.category_outlined,
                color: _alsoPersonal ? scheme.primary : null),
            title: const Text('Also save to my categories'),
            subtitle: Text(mixed
                ? 'Select only income or only expenses to use this'
                : 'Keeps it in your personal $_catType records too'),
            value: _alsoPersonal && !mixed,
            onChanged: mixed || _saving ? null : _togglePersonal,
          ),
          if (_alsoPersonal && !mixed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _loadingCats
                  ? const LinearProgressIndicator()
                  : _cats.isEmpty
                      ? Text(
                          'No $_catType categories yet. Add some in Settings.',
                          style: TextStyle(color: scheme.onSurfaceVariant))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final c in _cats)
                              ChoiceChip(
                                label: Text(c),
                                selected: c == _cat,
                                onSelected: _saving
                                    ? null
                                    : (_) => setState(() {
                                          _cat = c;
                                          _error = null;
                                        }),
                              ),
                          ],
                        ),
            ),
        ],
      ),
    );
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
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // Re-keyed so a newly linked workbook shows as selected.
                      key: ValueKey('${_workbook?.id}-${_workbooks.length}'),
                      initialValue: _workbook?.id,
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon:
                            const Icon(Icons.table_chart, color: _sheetGreen),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        for (final w in _workbooks)
                          DropdownMenuItem(
                            value: w.id,
                            child:
                                Text(w.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (id) {
                              final w = _workbooks.firstWhere((w) => w.id == id);
                              if (w.id != _workbook?.id) _selectWorkbook(w);
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Link another workbook',
                    icon: const Icon(Icons.add_link),
                    onPressed: _saving ? null : _addWorkbook,
                  ),
                ],
              ),

            // ── Sheet ────────────────────────────────────────────
            if (_workbook != null) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Sheet', style: theme.textTheme.titleSmall),
                  if (_sheets.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('(${_sheets.length})',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reload sheets',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadingSheets || _saving
                        ? null
                        : () => _selectWorkbook(_workbook!),
                  ),
                  if (_error == null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: _saving || _loadingSheets ? null : _newSheet,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loadingSheets)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                )
              else if (_sheets.isNotEmpty) ...[
                if (_sheets.length > 5) ...[
                  TextField(
                    controller: _filter,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search ${_sheets.length} sheets',
                      suffixIcon: _filter.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _filter.clear()),
                            ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _buildSheetList(theme, visibleSheets),
              ],
            ],

            if (_workbook != null && !_loadingWorkbooks) ...[
              const SizedBox(height: 16),
              _buildPersonalSection(theme),
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
                label: Text(
                  _sheet == null
                      ? 'Choose a sheet'
                      : _alsoPersonal && _cat != null
                          ? 'Record to "$_sheet" + $_cat'
                          : 'Record to "$_sheet"',
                  overflow: TextOverflow.ellipsis,
                ),
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
