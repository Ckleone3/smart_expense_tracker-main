import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'google_sheets_service.dart';
import 'sms_service.dart' as sms;

/// Undoes a business recording: deletes the row from the Google Sheet and puts
/// the transaction back in the To Sort list.
///
/// With [sheetAlreadyHandled] the sheet is not touched (used when the row
/// can't be reached and the user chooses to restore the transaction anyway).
/// Returns a short message for the user. Throws [SheetsException] if the row
/// couldn't be removed, in which case nothing is changed in the app.
Future<String> undoBusinessRecord(
  BusinessRecord r,
  sms.SmsService smsService, {
  bool sheetAlreadyHandled = false,
}) async {
  final sheets = GoogleSheetsService.instance;
  var removed = false;
  if (!sheetAlreadyHandled) {
    removed = await sheets.removeRow(r.spreadsheetId, r.sheet, r.transactionId);
  }

  var restored = false;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .doc(r.itemId)
          .update({'categoryId': null});
      restored = true;
    } catch (e) {
      log('Undo: Firestore restore skipped for ${r.itemId}: $e');
    }
  }
  final localId = r.localId ?? r.itemId;
  try {
    await smsService.updateTransactionCategory(localId, null);
    restored = true;
  } catch (e) {
    log('Undo: local restore skipped for $localId: $e');
  }

  await sheets.deleteRecord(r.itemId);

  final where = '${r.workbookName} › ${r.sheet}';
  final sheetPart = sheetAlreadyHandled
      ? 'Sheet left unchanged'
      : removed
          ? 'Removed from $where'
          : 'Row was already gone from $where';
  return restored
      ? '$sheetPart · back in To Sort'
      : "$sheetPart · couldn't find the transaction to move back to To Sort";
}
