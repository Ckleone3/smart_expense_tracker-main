import 'dart:convert';
import 'dart:developer';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'rent_sms_parser.dart';

/// Prefix written into a transaction's `categoryId` once it has been recorded
/// to a business workbook, so it leaves the "To Sort" list and is easy to tell
/// apart from personal categories.
const String kBusinessCategoryPrefix = 'Business:';

/// A Google Sheets workbook the user has linked as a business backend. Each
/// worksheet (tab) inside it is a payable, e.g. "Constructions".
class BusinessWorkbook {
  final String id;
  final String name;
  final String spreadsheetId;

  BusinessWorkbook(
      {required this.id, required this.name, required this.spreadsheetId});

  String get url => 'https://docs.google.com/spreadsheets/d/$spreadsheetId';

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'spreadsheetId': spreadsheetId};

  factory BusinessWorkbook.fromMap(Map m) => BusinessWorkbook(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Workbook',
        spreadsheetId: m['spreadsheetId'] as String,
      );
}

/// One transaction to be written as a row.
class SheetEntry {
  final String transactionId;
  final DateTime date;
  final String type;
  final String description;
  final double amount;
  final String rawSms;

  SheetEntry({
    required this.transactionId,
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
    required this.rawSms,
  });

  /// True if this is money coming in (Income). Uses the app's type when it is
  /// Income/Expense, otherwise works it out from the SMS wording.
  bool get isIncoming {
    final t = type.toLowerCase();
    if (t == 'income') return true;
    if (t == 'expense') return false;
    return RentSmsParser.parse(rawSms, smsDate: date)?.bank == 'In';
  }

  /// M-Pesa / bank reference code from the SMS, e.g. "TKL3ABC123".
  String get refNo {
    final p = RentSmsParser.parse(rawSms, smsDate: date);
    if (p != null) {
      if (p.mpesaRef.isNotEmpty) return p.mpesaRef;
      if (p.ref.isNotEmpty) return p.ref;
    }
    // M-Pesa confirmations start with the code: "TKL3ABC123 Confirmed. ..."
    return RegExp(r'^\s*([A-Z0-9]{10})\s+Confirmed', caseSensitive: false)
            .firstMatch(rawSms)
            ?.group(1)
            ?.toUpperCase() ??
        '';
  }
}

class AppendResult {
  /// Transaction ids written in this call.
  final List<String> written;

  /// Transaction ids skipped because the sheet already had them.
  final List<String> duplicates;

  AppendResult(this.written, this.duplicates);
}

/// A transaction that was recorded to a business sheet, kept so it can be
/// found again and undone.
class BusinessRecord {
  /// Id of the item in the To Sort list (Firestore doc id).
  final String itemId;

  /// Id in the local SMS store, when it differs from [itemId] (free users).
  final String? localId;

  /// Value written to the sheet's Transaction Id column.
  final String transactionId;
  final String workbookId;
  final String workbookName;
  final String spreadsheetId;
  final String sheet;
  final String description;
  final double amount;
  final bool isIncoming;
  final DateTime date;
  final DateTime recordedAt;

  BusinessRecord({
    required this.itemId,
    this.localId,
    required this.transactionId,
    required this.workbookId,
    required this.workbookName,
    required this.spreadsheetId,
    required this.sheet,
    required this.description,
    required this.amount,
    required this.isIncoming,
    required this.date,
    required this.recordedAt,
  });

  Map<String, dynamic> toMap() => {
        'itemId': itemId,
        'localId': localId,
        'transactionId': transactionId,
        'workbookId': workbookId,
        'workbookName': workbookName,
        'spreadsheetId': spreadsheetId,
        'sheet': sheet,
        'description': description,
        'amount': amount,
        'isIncoming': isIncoming,
        'date': date.toIso8601String(),
        'recordedAt': recordedAt.toIso8601String(),
      };

  static BusinessRecord? fromMap(Object? v) {
    if (v is! Map || v['itemId'] is! String || v['spreadsheetId'] is! String) {
      return null;
    }
    return BusinessRecord(
      itemId: v['itemId'] as String,
      localId: v['localId'] as String?,
      transactionId: (v['transactionId'] as String?) ?? v['itemId'] as String,
      workbookId: (v['workbookId'] as String?) ?? '',
      workbookName: (v['workbookName'] as String?) ?? 'Workbook',
      spreadsheetId: v['spreadsheetId'] as String,
      sheet: (v['sheet'] as String?) ?? '',
      description: (v['description'] as String?) ?? '',
      amount: ((v['amount'] as num?) ?? 0).toDouble(),
      isIncoming: v['isIncoming'] == true,
      date: DateTime.tryParse(v['date'] as String? ?? '') ?? DateTime.now(),
      recordedAt:
          DateTime.tryParse(v['recordedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class SheetsException implements Exception {
  final String message;
  SheetsException(this.message);
  @override
  String toString() => message;
}

/// Records business transactions into Google Sheets via the Sheets API,
/// authorised with the user's Google account.
class GoogleSheetsService {
  GoogleSheetsService._();
  static final GoogleSheetsService instance = GoogleSheetsService._();

  static const _scope = 'https://www.googleapis.com/auth/spreadsheets';
  static const _api = 'https://sheets.googleapis.com/v4/spreadsheets';
  static const _boxName = 'business_workbooks';
  static const _lastKey = '_last';

  /// Header row written to an empty sheet.
  static const defaultHeaders = [
    'Date',
    'Description',
    'IN',
    'OUT',
    'Ref No',
    'Transaction Id',
    'Recorded By',
  ];

  final GoogleSignIn _signIn = GoogleSignIn(scopes: ['email', _scope]);

  // ─── Linked workbooks (stored locally) ─────────────────────────────────────

  Future<Box> _box() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    await Hive.initFlutter();
    return Hive.openBox(_boxName);
  }

  Future<List<BusinessWorkbook>> workbooks() async {
    final box = await _box();
    final list = <BusinessWorkbook>[];
    for (final key in box.keys) {
      if (key == _lastKey) continue; // preference, not a workbook
      final v = box.get(key);
      if (v is Map && v['id'] is String && v['spreadsheetId'] is String) {
        list.add(BusinessWorkbook.fromMap(v));
      }
    }
    return list
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> saveWorkbook(BusinessWorkbook w) async =>
      (await _box()).put(w.id, w.toMap());

  Future<void> deleteWorkbook(String id) async => (await _box()).delete(id);

  /// Remembers the last workbook/sheet used so the picker can preselect it.
  Future<void> rememberLast(String workbookId, String sheet) async {
    final box = await _box();
    await box.put(_lastKey, {'workbookId': workbookId, 'sheet': sheet});
  }

  Future<({String? workbookId, String? sheet})> last() async {
    final v = (await _box()).get(_lastKey);
    if (v is Map) {
      return (
        workbookId: v['workbookId'] as String?,
        sheet: v['sheet'] as String?
      );
    }
    return (workbookId: null, sheet: null);
  }

  // ─── Recorded transactions (for undo) ──────────────────────────────────────

  static const _recordsBoxName = 'business_records';

  Future<Box> _recordsBox() async {
    if (Hive.isBoxOpen(_recordsBoxName)) return Hive.box(_recordsBoxName);
    await Hive.initFlutter();
    return Hive.openBox(_recordsBoxName);
  }

  Future<void> saveRecords(List<BusinessRecord> records) async {
    final box = await _recordsBox();
    await box.putAll({for (final r in records) r.itemId: r.toMap()});
  }

  /// Newest first.
  Future<List<BusinessRecord>> records() async {
    final box = await _recordsBox();
    return box.values
        .map(BusinessRecord.fromMap)
        .whereType<BusinessRecord>()
        .toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  }

  Future<void> deleteRecord(String itemId) async =>
      (await _recordsBox()).delete(itemId);

  /// Accepts a full Google Sheets URL or a bare spreadsheet id.
  static String? parseSpreadsheetId(String input) {
    final s = input.trim();
    final m = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(s);
    if (m != null) return m.group(1);
    if (RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(s)) return s;
    return null;
  }

  // ─── Auth ──────────────────────────────────────────────────────────────────

  String? get signedInEmail => _signIn.currentUser?.email;

  Future<GoogleSignInAccount> _account() async {
    var acct = _signIn.currentUser ?? await _signIn.signInSilently();
    acct ??= await _signIn.signIn();
    if (acct == null) {
      throw SheetsException('Google sign-in was cancelled.');
    }
    final granted = await _signIn.requestScopes([_scope]);
    if (!granted) {
      throw SheetsException(
          'Permission to edit Google Sheets is needed to record business transactions.');
    }
    return acct;
  }

  /// Lets the user pick a different Google account.
  Future<String?> switchAccount() async {
    await _signIn.signOut();
    return (await _account()).email;
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Object? body,
    bool retried = false,
  }) async {
    final acct = await _account();
    final headers = {
      ...await acct.authHeaders,
      'Content-Type': 'application/json',
    };
    final req = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(seconds: 30)));

    if (res.statusCode == 401 && !retried) {
      // Token expired/revoked: drop it and try once more.
      await acct.clearAuthCache();
      return _send(method, uri, body: body, retried: true);
    }
    if (res.statusCode >= 400) throw _error(res, acct.email);
    return res;
  }

  SheetsException _error(http.Response res, String email) {
    String msg = '';
    try {
      msg = (jsonDecode(res.body)['error']?['message'] as String?) ?? '';
    } catch (_) {}
    log('Sheets API ${res.statusCode}: ${res.body}');
    if (msg.contains('has not been used') || msg.contains('is disabled')) {
      return SheetsException(
          'The Google Sheets API is not enabled for this app\'s Google Cloud project.');
    }
    switch (res.statusCode) {
      case 403:
        return SheetsException(
            '$email does not have edit access to this workbook. Share it with this account as an Editor.');
      case 404:
        return SheetsException(
            'Workbook not found. Check the link, or that it is shared with $email.');
      case 400:
        return SheetsException(msg.isEmpty ? 'Invalid request.' : msg);
      default:
        return SheetsException(
            'Google Sheets error (${res.statusCode})${msg.isEmpty ? '' : ': $msg'}');
    }
  }

  // ─── Sheets API ────────────────────────────────────────────────────────────

  /// Workbook title and the names of its visible worksheets, in tab order.
  Future<({String title, List<String> sheets})> describe(
      String spreadsheetId) async {
    final uri = Uri.parse('$_api/$spreadsheetId').replace(queryParameters: {
      'fields': 'properties.title,sheets.properties(title,index,hidden)',
    });
    final data = jsonDecode((await _send('GET', uri)).body) as Map;
    final sheets = ((data['sheets'] as List?) ?? [])
        .map((s) => s['properties'] as Map)
        .where((p) => p['hidden'] != true)
        .toList()
      ..sort((a, b) => ((a['index'] ?? 0) as int).compareTo(b['index'] ?? 0));
    return (
      title: (data['properties']?['title'] as String?) ?? 'Workbook',
      sheets: sheets.map((p) => p['title'] as String).toList(),
    );
  }

  /// Adds a new worksheet (tab) and writes the default headers into it.
  Future<void> createSheet(String spreadsheetId, String title) async {
    await _send('POST', Uri.parse('$_api/$spreadsheetId:batchUpdate'), body: {
      'requests': [
        {
          'addSheet': {
            'properties': {'title': title}
          }
        }
      ]
    });
    await _send(
      'PUT',
      Uri.parse('$_api/$spreadsheetId/values/${_range(title, 'A1')}')
          .replace(queryParameters: {'valueInputOption': 'RAW'}),
      body: {
        'values': [defaultHeaders]
      },
    );
  }

  /// Sheet id (needed for row operations) and its current row count.
  Future<({int sheetId, int rowCount})> _sheetProps(
      String spreadsheetId, String sheet) async {
    final uri = Uri.parse('$_api/$spreadsheetId').replace(queryParameters: {
      'fields': 'sheets.properties(sheetId,title,gridProperties.rowCount)',
    });
    final data = jsonDecode((await _send('GET', uri)).body) as Map;
    for (final s in (data['sheets'] as List?) ?? const []) {
      final p = s['properties'] as Map;
      if (p['title'] == sheet) {
        return (
          sheetId: (p['sheetId'] as num).toInt(),
          rowCount: ((p['gridProperties']?['rowCount'] ?? 1000) as num).toInt(),
        );
      }
    }
    throw SheetsException('Sheet "$sheet" no longer exists in this workbook.');
  }

  /// Reads the first rows of [sheet] and works out where the header row is and
  /// which column holds which field. Returns null for a completely empty sheet.
  Future<_Layout?> _layout(String spreadsheetId, String sheet) async {
    final res = await _send(
        'GET',
        Uri.parse(
            '$_api/$spreadsheetId/values/${_range(sheet, '1:$_headerScanRows')}'));
    final rows = _rows(res.body);
    if (rows.every((r) => r.every((c) => c.trim().isEmpty))) return null;
    final idx = findHeaderRow(rows);
    if (idx < 0) {
      throw SheetsException(
          'Could not find a header row in "$sheet". Add one with: ${defaultHeaders.join(', ')}.');
    }
    return _Layout(idx + 1, rows[idx].map(_fieldFor).toList());
  }

  /// Writes [entries] into [sheet] on the rows right after the last record.
  ///
  /// * The header row is found automatically (anywhere in the first
  ///   [_headerScanRows] rows) and columns are matched by header name.
  /// * The next free row is worked out from our own columns only, so formula,
  ///   checkbox or other columns filled down the sheet, and blank gaps in the
  ///   data, don't throw it off.
  /// * Only our columns are written; nothing is inserted or shifted, so other
  ///   columns and formulas in the sheet are left alone.
  /// * Transactions already in the Transaction Id column are skipped.
  Future<AppendResult> append(
    String spreadsheetId,
    String sheet,
    List<SheetEntry> entries, {
    String recordedBy = '',
  }) async {
    final found = await _layout(spreadsheetId, sheet);
    final wasEmpty = found == null;
    final layout =
        found ?? _Layout(1, defaultHeaders.map(_fieldFor).toList());
    final writes = <Map<String, dynamic>>[
      if (wasEmpty)
        {
          'range': _a1(sheet, 'A1'),
          'majorDimension': 'ROWS',
          'values': [defaultHeaders],
        }
    ];

    final ourCols = [
      for (var i = 0; i < layout.fields.length; i++)
        if (layout.fields[i] != null) i
    ];
    final lastCol = _columnLetter(ourCols.last);

    // Everything under the header, across our columns.
    final data = wasEmpty
        ? <List<String>>[]
        : _rows((await _send(
                'GET',
                Uri.parse(
                    '$_api/$spreadsheetId/values/${_range(sheet, 'A${layout.headerRow + 1}:$lastCol')}')))
            .body);

    final idCol = layout.fields.indexOf(_Field.transactionId);
    final existing = <String>{
      if (idCol >= 0)
        for (final r in data)
          if (idCol < r.length && r[idCol].trim().isNotEmpty) r[idCol].trim()
    };

    final fresh =
        entries.where((e) => !existing.contains(e.transactionId)).toList();
    final dupes = entries
        .where((e) => existing.contains(e.transactionId))
        .map((e) => e.transactionId)
        .toList();
    if (fresh.isEmpty) return AppendResult(const [], dupes);

    final first = layout.headerRow + 1 + nextFreeRow(data, ourCols);
    final last = first + fresh.length - 1;

    // Make room if the sheet's grid is too small.
    final props = await _sheetProps(spreadsheetId, sheet);
    if (last > props.rowCount) {
      await _send('POST', Uri.parse('$_api/$spreadsheetId:batchUpdate'), body: {
        'requests': [
          {
            'appendDimension': {
              'sheetId': props.sheetId,
              'dimension': 'ROWS',
              'length': last - props.rowCount + 100,
            }
          }
        ]
      });
    }

    // One write per column we own, so neighbouring columns stay untouched.
    for (final c in ourCols) {
      final col = _columnLetter(c);
      writes.add({
        'range': _a1(sheet, '$col$first:$col$last'),
        'majorDimension': 'COLUMNS',
        'values': [
          [for (final e in fresh) _value(layout.fields[c], e, recordedBy)]
        ],
      });
    }

    await _send('POST', Uri.parse('$_api/$spreadsheetId/values:batchUpdate'),
        body: {'valueInputOption': 'USER_ENTERED', 'data': writes});

    return AppendResult(fresh.map((e) => e.transactionId).toList(), dupes);
  }

  /// Deletes the row(s) holding [transactionId] from [sheet]. Returns false if
  /// no such row was found (e.g. someone already removed it).
  Future<bool> removeRow(
      String spreadsheetId, String sheet, String transactionId) async {
    final layout = await _layout(spreadsheetId, sheet);
    if (layout == null) return false;
    final idCol = layout.fields.indexOf(_Field.transactionId);
    if (idCol < 0) {
      throw SheetsException(
          '"$sheet" has no Transaction Id column, so the row can\'t be found. Delete it by hand.');
    }
    final col = _columnLetter(idCol);
    final res = await _send(
        'GET',
        Uri.parse(
            '$_api/$spreadsheetId/values/${_range(sheet, '$col${layout.headerRow + 1}:$col')}'));
    final rows = _rows(res.body);
    final matches = <int>[
      for (var i = 0; i < rows.length; i++)
        if (rows[i].isNotEmpty && rows[i].first.trim() == transactionId)
          layout.headerRow + 1 + i // 1-based sheet row
    ];
    if (matches.isEmpty) return false;

    final props = await _sheetProps(spreadsheetId, sheet);
    await _send('POST', Uri.parse('$_api/$spreadsheetId:batchUpdate'), body: {
      'requests': [
        // Bottom-up so earlier deletions don't shift later ones.
        for (final r in matches.reversed)
          {
            'deleteDimension': {
              'range': {
                'sheetId': props.sheetId,
                'dimension': 'ROWS',
                'startIndex': r - 1,
                'endIndex': r,
              }
            }
          }
      ]
    });
    return true;
  }

  // ─── Layout helpers (pure, unit-tested) ────────────────────────────────────

  static const _headerScanRows = 10;

  /// Index of the row (within [rows]) that looks most like a header row, or -1.
  /// A row needs at least two recognised column names to count.
  static int findHeaderRow(List<List<String>> rows) {
    var best = -1, bestScore = 1;
    for (var i = 0; i < rows.length; i++) {
      final score = rows[i].map(_fieldFor).whereType<_Field>().toSet().length;
      if (score > bestScore) {
        best = i;
        bestScore = score;
      }
    }
    return best;
  }

  /// Offset (from the first row under the header) of the row after the last
  /// one that has a value in any of [ourCols].
  static int nextFreeRow(List<List<String>> data, List<int> ourCols) {
    for (var i = data.length - 1; i >= 0; i--) {
      final r = data[i];
      if (ourCols.any((c) => c < r.length && r[c].trim().isNotEmpty)) {
        return i + 1;
      }
    }
    return 0;
  }

  static List<List<String>> _rows(String body) =>
      ((jsonDecode(body)['values'] as List?) ?? const [])
          .map((r) => (r as List).map((c) => c.toString()).toList())
          .toList();

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// A1 range for a sheet, quoting the name: 'O''Brien'!A1
  static String _a1(String sheet, String a1) =>
      "'${sheet.replaceAll("'", "''")}'!$a1";

  /// [_a1], URL-encoded for use in a request path.
  static String _range(String sheet, String a1) =>
      Uri.encodeComponent(_a1(sheet, a1));

  static String _columnLetter(int index) {
    var n = index + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static _Field? _fieldFor(String header) {
    final h = header.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (h.isEmpty) return null;
    const aliases = {
      _Field.date: ['date', 'transactiondate', 'txndate', 'day', 'datepaid'],
      _Field.description: [
        'description', 'details', 'particulars', 'narration', 'payee',
        'item', 'memo', 'paidto', 'name'
      ],
      _Field.amountIn: [
        'in', 'moneyin', 'income', 'received', 'credit', 'cr', 'amountin'
      ],
      _Field.amountOut: [
        'out', 'moneyout', 'expense', 'expenses', 'debit', 'dr', 'spent',
        'amountout'
      ],
      _Field.refNo: [
        'refno', 'ref', 'reference', 'referenceno', 'refnumber', 'mpesaref',
        'mpesacode', 'code', 'receipt', 'receiptno'
      ],
      _Field.transactionId: ['transactionid', 'txnid', 'transactioncode'],
      _Field.recordedBy: ['recordedby', 'enteredby', 'user', 'by'],
    };
    for (final entry in aliases.entries) {
      if (entry.value.contains(h)) return entry.key;
    }
    if (h.startsWith('amount') ||
        const ['value', 'cost', 'ksh', 'total'].contains(h)) {
      return _Field.amount;
    }
    return null;
  }

  static Object _value(_Field? f, SheetEntry e, String recordedBy) {
    switch (f) {
      case _Field.date:
        return DateFormat('yyyy-MM-dd HH:mm').format(e.date);
      case _Field.amount:
        return e.amount;
      case _Field.amountIn:
        return e.isIncoming ? e.amount : '';
      case _Field.amountOut:
        return e.isIncoming ? '' : e.amount;
      case _Field.description:
        return _text(e.description);
      case _Field.refNo:
        return _text(e.refNo);
      case _Field.transactionId:
        return _text(e.transactionId);
      case _Field.recordedBy:
        return _text(recordedBy);
      case null:
        return '';
    }
  }

  /// Rows are written USER_ENTERED (so dates/numbers parse), which means text
  /// beginning with = + - @ would be treated as a formula. Force it to text.
  static String _text(String s) =>
      RegExp(r'^[=+\-@]').hasMatch(s) ? "'$s" : s;
}

enum _Field {
  date,
  description,
  amount,
  amountIn,
  amountOut,
  refNo,
  transactionId,
  recordedBy,
}

class _Layout {
  /// 1-based row number of the header row.
  final int headerRow;
  final List<_Field?> fields;
  _Layout(this.headerRow, this.fields);
}
